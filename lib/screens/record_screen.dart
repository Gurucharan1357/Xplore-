import 'dart:async';
import 'dart:convert';
import 'dart:typed_data'; 
import 'dart:ui' as ui;   
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;
import 'package:vibration/vibration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; 

// Safely loads the token from your .env file
String get MAPBOX_ACCESS_TOKEN => dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

const String styleDark = 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';

// We use a getter for these so they pull the token dynamically when needed
String get styleStandard => '{"version": 8,"sources": {"mapbox-outdoors": {"type": "raster","tiles": ["https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$MAPBOX_ACCESS_TOKEN"],"tileSize": 256}},"layers": [{"id": "outdoors-layer","type": "raster","source": "mapbox-outdoors"}]}';
String get styleSatellite => '{"version": 8,"sources": {"mapbox-satellite": {"type": "raster","tiles": ["https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$MAPBOX_ACCESS_TOKEN"],"tileSize": 256}},"layers": [{"id": "satellite-layer","type": "raster","source": "mapbox-satellite"}]}';

class RecordScreen extends StatefulWidget {
  static final ValueNotifier<bool> isNavHidden = ValueNotifier(false);
  final Map<String, dynamic>? trekToFollow;

  const RecordScreen({super.key, this.trekToFollow});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  MapLibreMapController? _mapController;
  
  bool _isRecording = false;
  bool _isPaused = false;
  String _currentMapStyle = styleDark;
  bool _isHudExpanded = false; 

  Timer? _stopwatchTimer;
  StreamSubscription<Map<String, dynamic>?>? _serviceSubscription;
  int _elapsedSeconds = 0;
  String _elapsedTime = "00:00:00";
  String _distance = "0.00";
  String _pace = "--:--";
  String _elevation = "0";

  List<mt.LatLng> _routeGeometryPoints = [];
  bool _isOffRoute = false;

  @override
  void didUpdateWidget(RecordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trekToFollow != oldWidget.trekToFollow && widget.trekToFollow != null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _drawTrekRoute();
      });
    }
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _serviceSubscription?.cancel();
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    _recenterMap();
  }

  void _onStyleLoaded() {
    _drawTrekRoute();
  }

  Future<Uint8List> _generateIconBytes(IconData icon, Color color) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 100.0, 
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0.0, 0.0));
    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(textPainter.width.toInt(), textPainter.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _drawTrekRoute() async {
    if (widget.trekToFollow == null || _mapController == null) return;
    dynamic geojsonData = widget.trekToFollow!['route_geom'];
    if (geojsonData == null) return;

    if (geojsonData is String) {
      try { geojsonData = jsonDecode(geojsonData); } catch (_) { return; }
    }

    if (geojsonData is Map<String, dynamic> && geojsonData['coordinates'] != null) {
      _routeGeometryPoints.clear();
      for (var coord in geojsonData['coordinates']) {
        _routeGeometryPoints.add(mt.LatLng(coord[1], coord[0]));
      }
    }

    if (geojsonData is Map<String, dynamic> && geojsonData['type'] == 'LineString') {
      geojsonData = {
        "type": "FeatureCollection",
        "features": [{"type": "Feature","properties": {},"geometry": geojsonData}]
      };
    }

    try {
      try { await _mapController!.removeLayer("trek-layer"); } catch (_) {}
      try { await _mapController!.removeSource("trek-source"); } catch (_) {}
      try { await _mapController!.removeLayer("start-layer"); } catch (_) {}
      try { await _mapController!.removeSource("start-source"); } catch (_) {}
      try { await _mapController!.removeLayer("end-layer"); } catch (_) {}
      try { await _mapController!.removeSource("end-source"); } catch (_) {}

      await _mapController!.addSource("trek-source", GeojsonSourceProperties(data: geojsonData));
      await _mapController!.addLineLayer("trek-source", "trek-layer", const LineLayerProperties(
        lineColor: "#D4FF00", lineWidth: 6.0, lineCap: "round", lineJoin: "round",
      ));

      if (_routeGeometryPoints.isNotEmpty) {
        final start = _routeGeometryPoints.first;
        final end = _routeGeometryPoints.last;

        await _mapController!.addSource("start-source", GeojsonSourceProperties(data: {
          "type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [start.longitude, start.latitude]}}]
        }));
        await _mapController!.addCircleLayer("start-source", "start-layer", const CircleLayerProperties(
          circleRadius: 8.0, circleColor: "#00FF00", circleStrokeWidth: 3.0, circleStrokeColor: "#161922",
        ));

        try {
          final Uint8List flagBytes = await _generateIconBytes(Icons.flag_rounded, Colors.redAccent);
          await _mapController!.addImage("end-flag-icon", flagBytes);
        } catch (_) {} 

        await _mapController!.addSource("end-source", GeojsonSourceProperties(data: {
          "type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [end.longitude, end.latitude]}}]
        }));
        
        await _mapController!.addSymbolLayer("end-source", "end-layer", const SymbolLayerProperties(
          iconImage: "end-flag-icon",
          iconSize: 0.6,
          iconAnchor: "bottom-left", 
        ));
      }

      _mapController!.animateCamera(CameraUpdate.zoomTo(14.0));
    } catch (e) {
      debugPrint("Error drawing route: $e");
    }
  }

  void _recenterMap() {
    if (_mapController != null) {
      _mapController!.updateMyLocationTrackingMode(MyLocationTrackingMode.trackingCompass);
    }
  }

  void _resetCompass() {
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.bearingTo(0.0));
    }
  }

  void _startStopwatch() {
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
        int h = _elapsedSeconds ~/ 3600;
        int m = (_elapsedSeconds % 3600) ~/ 60;
        int s = _elapsedSeconds % 60;
        _elapsedTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      });
    });
  }

  void _toggleTracking() async {
    if (!_isRecording) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      }

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _isHudExpanded = true; 
        RecordScreen.isNavHidden.value = true; 
        _mapController?.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
      });

      final service = FlutterBackgroundService();
      await service.startService();
      _startStopwatch();

      _serviceSubscription = service.on('update').listen((event) async {
        if (event != null && mounted && !_isPaused) {
          setState(() {
            double speed = event['speed'] ?? 0.0;
            double alt = event['altitude'] ?? 0.0;
            double lat = event['lat'] ?? 0.0;
            double lng = event['lng'] ?? 0.0;
            
            _elevation = alt.toStringAsFixed(0);
            
            if (speed > 0.5) { 
              double paceMinPerKm = (60 / (speed * 3.6));
              int pMin = paceMinPerKm.floor();
              int pSec = ((paceMinPerKm - pMin) * 60).round();
              _pace = "$pMin:${pSec.toString().padLeft(2, '0')}";
            }

            if (_routeGeometryPoints.isNotEmpty) {
              mt.LatLng currentLoc = mt.LatLng(lat, lng);
              bool isOnRoute = mt.PolygonUtil.isLocationOnPath(currentLoc, _routeGeometryPoints, false, tolerance: 40.0);
              
              if (!isOnRoute && !_isOffRoute) {
                _isOffRoute = true;
                Vibration.vibrate(pattern: [500, 1000, 500, 1000]); 
              } else if (isOnRoute && _isOffRoute) {
                _isOffRoute = false;
              }
            }
          });
        }
      });

    } else if (_isRecording && !_isPaused) {
      setState(() => _isPaused = true);
      _stopwatchTimer?.cancel();
    } else if (_isRecording && _isPaused) {
      setState(() => _isPaused = false);
      _startStopwatch();
    }
  }

  void _finishTrek() {
    _stopwatchTimer?.cancel();
    _serviceSubscription?.cancel();
    FlutterBackgroundService().invoke("stopService");

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _isHudExpanded = false; 
      _isOffRoute = false; 
      RecordScreen.isNavHidden.value = false; 
      _elapsedSeconds = 0;
      _elapsedTime = "00:00:00";
      _distance = "0.00";
      _pace = "--:--";
      _elevation = "0";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trek Finished & Saved!'), backgroundColor: Colors.green)
    );
  }

  void _showMapStyleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('Map Type', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMapTypeOption('Dark', Icons.dark_mode, styleDark),
                _buildMapTypeOption('Outdoors', Icons.terrain, styleStandard),
                _buildMapTypeOption('Satellite', Icons.satellite, styleSatellite),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      )
    );
  }

  Widget _buildMapTypeOption(String label, IconData icon, String styleString) {
    final isSelected = _currentMapStyle == styleString;
    return GestureDetector(
      onTap: () {
        setState(() => _currentMapStyle = styleString);
        Navigator.pop(context);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: isSelected ? neonAccent.withOpacity(0.2) : bgColor, shape: BoxShape.circle, border: Border.all(color: isSelected ? neonAccent : Colors.white10, width: 2)),
            child: Icon(icon, color: isSelected ? neonAccent : Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: isSelected ? neonAccent : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded, 
              styleString: _currentMapStyle, 
              initialCameraPosition: const CameraPosition(target: LatLng(12.2958, 76.6394), zoom: 15.0),
              myLocationEnabled: true,
              myLocationRenderMode: MyLocationRenderMode.compass, 
              myLocationTrackingMode: MyLocationTrackingMode.trackingCompass,
              compassEnabled: false, 
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isOffRoute ? Colors.redAccent.withOpacity(0.9) : Colors.black.withOpacity(0.7), 
                    borderRadius: BorderRadius.circular(20), 
                    border: Border.all(color: _isOffRoute ? Colors.red : Colors.white10)
                  ),
                  child: Row(
                    children: [
                      Icon(_isOffRoute ? Icons.warning_amber_rounded : Icons.satellite_alt, color: _isOffRoute ? Colors.white : neonAccent, size: 16),
                      const SizedBox(width: 8),
                      Text(_isOffRoute ? 'OFF ROUTE!' : 'GPS Acquired', style: TextStyle(color: _isOffRoute ? Colors.white : neonAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _resetCompass,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), shape: BoxShape.circle, border: Border.all(color: Colors.white10)),
                    child: const Icon(Icons.explore, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FloatingActionButton(heroTag: 'layers_btn', backgroundColor: cardSurface, mini: true, onPressed: _showMapStyleSelector, child: const Icon(Icons.layers, color: Colors.white)),
                      const SizedBox(height: 12),
                      FloatingActionButton(heroTag: 'recenter_btn', backgroundColor: cardSurface, mini: true, onPressed: _recenterMap, child: const Icon(Icons.my_location, color: neonAccent)),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastOutSlowIn,
                  decoration: BoxDecoration(color: cardSurface, borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, -5))]),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isRecording)
                          GestureDetector(
                            onTap: () => setState(() => _isHudExpanded = !_isHudExpanded),
                            onVerticalDragUpdate: (details) {
                              if (details.primaryDelta! > 2) setState(() => _isHudExpanded = false);
                              else if (details.primaryDelta! < -2) setState(() => _isHudExpanded = true);
                            },
                            child: Container(
                              color: Colors.transparent, 
                              width: double.infinity,
                              padding: const EdgeInsets.only(top: 16, bottom: 8),
                              child: Column(
                                children: [
                                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(height: 16),
                                  Text(_elapsedTime, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 2)),
                                  const Text('ELAPSED TIME', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                ],
                              ),
                            ),
                          )
                        else const SizedBox(height: 24), 
                        Padding(
                          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isRecording)
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.fastOutSlowIn,
                                  child: _isHudExpanded 
                                    ? Column(
                                        children: [
                                          const SizedBox(height: 24),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: [
                                              _buildStatColumn(_distance, 'km', 'DISTANCE'),
                                              Container(height: 40, width: 1, color: Colors.white10),
                                              _buildStatColumn(_pace, '/km', 'PACE'),
                                              Container(height: 40, width: 1, color: Colors.white10),
                                              _buildStatColumn(_elevation, 'm', 'ELEV GAIN'),
                                            ],
                                          ),
                                          const SizedBox(height: 32),
                                        ],
                                      )
                                    : const SizedBox(height: 24),
                                ),
                              if (!_isRecording)
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                                    onPressed: _toggleTracking,
                                    icon: const Icon(Icons.play_arrow, size: 28),
                                    label: const Text('START TREK', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 56,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: _isPaused ? neonAccent : Colors.orangeAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                                          onPressed: _toggleTracking,
                                          icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 24),
                                          label: Text(_isPaused ? 'RESUME' : 'PAUSE', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                        ),
                                      ),
                                    ),
                                    if (_isPaused) ...[
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: SizedBox(
                                          height: 56,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                                            onPressed: _finishTrek,
                                            child: const Text('FINISH', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                          ),
                                        ),
                                      ),
                                    ]
                                  ],
                                )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String unit, String label) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(width: 2),
            Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }
}