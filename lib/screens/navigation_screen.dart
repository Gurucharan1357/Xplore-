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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

String get MAPBOX_ACCESS_TOKEN => dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);
const String styleDark = 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';
String get styleStandard => '{"version": 8,"sources": {"mapbox-outdoors": {"type": "raster","tiles": ["https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$MAPBOX_ACCESS_TOKEN"],"tileSize": 256}},"layers": [{"id": "outdoors-layer","type": "raster","source": "mapbox-outdoors"}]}';
String get styleSatellite => '{"version": 8,"sources": {"mapbox-satellite": {"type": "raster","tiles": ["https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$MAPBOX_ACCESS_TOKEN"],"tileSize": 256}},"layers": [{"id": "satellite-layer","type": "raster","source": "mapbox-satellite"}]}';

class NavigationScreen extends StatefulWidget {
  final Map<String, dynamic> trekToFollow;

  const NavigationScreen({super.key, required this.trekToFollow});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  MapLibreMapController? _mapController;
  
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isHudExpanded = false; 
  bool _isReversed = false; 
  String _currentMapStyle = styleDark; 

  Timer? _stopwatchTimer;
  StreamSubscription<Map<String, dynamic>?>? _serviceSubscription;
  int _elapsedSeconds = 0;
  String _elapsedTime = "00:00:00";
  String _distance = "0.00";
  String _pace = "--:--";
  String _elevation = "0";

  List<mt.LatLng> _routeGeometryPoints = [];
  List<mt.LatLng> _actualRecordedPoints = []; 
  bool _isOffRoute = false;

  @override
  void initState() {
    super.initState();
    _parseRouteData();
  }

  // UPDATED BILINGUAL PARSING LOGIC
  void _parseRouteData() {
    _routeGeometryPoints.clear();
    final routeData = widget.trekToFollow['route_geojson'] ?? widget.trekToFollow['route_geom'];

    if (routeData != null) {
      if (routeData is String && routeData.contains('LINESTRING')) {
        final cleaned = routeData.replaceAll(RegExp(r'SRID=\d+;'), '').replaceAll('LINESTRING(', '').replaceAll(')', '');
        final pairs = cleaned.split(',');
        for (var pair in pairs) {
          final coords = pair.trim().split(RegExp(r'\s+'));
          if (coords.length >= 2) {
            final lon = double.tryParse(coords[0]);
            final lat = double.tryParse(coords[1]);
            if (lon != null && lat != null) _routeGeometryPoints.add(mt.LatLng(lat, lon));
          }
        }
      } else {
        dynamic parsed = routeData;
        if (routeData is String) {
          try { parsed = jsonDecode(routeData); } catch (_) {}
        }

        if (parsed is List) {
          for (var p in parsed) {
            if (p is Map) {
              final lat = (p['lat'] as num?)?.toDouble();
              final lng = (p['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) _routeGeometryPoints.add(mt.LatLng(lat, lng));
            } else if (p is List && p.length >= 2) {
              _routeGeometryPoints.add(mt.LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()));
            }
          }
        } else if (parsed is Map) {
          final coordinates = parsed['coordinates'] ?? parsed['geometry']?['coordinates'] ?? [];
          for (var c in coordinates) {
            if (c is List && c.length >= 2) _routeGeometryPoints.add(mt.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
          }
        }
      }
    }

    if (_isReversed) {
      _routeGeometryPoints = _routeGeometryPoints.reversed.toList();
    }
  }

  void _toggleReverse() async {
    if (_isRecording) return; 
    Vibration.vibrate(duration: 50);
    
    setState(() {
      _isReversed = !_isReversed;
    });
    
    _parseRouteData(); 
    
    if (_mapController != null && _routeGeometryPoints.isNotEmpty) {
      List<List<double>> coords = _routeGeometryPoints.map((p) => [p.longitude, p.latitude]).toList();
      
      await _mapController!.setGeoJsonSource("trek-source", {
        "type": "FeatureCollection",
        "features": [{"type": "Feature", "geometry": {"type": "LineString", "coordinates": coords}}]
      });
      
      final start = _routeGeometryPoints.first;
      await _mapController!.setGeoJsonSource("start-source", {
        "type": "FeatureCollection",
        "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [start.longitude, start.latitude]}}]
      });
      
      final end = _routeGeometryPoints.last;
      await _mapController!.setGeoJsonSource("end-source", {
        "type": "FeatureCollection",
        "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [end.longitude, end.latitude]}}]
      });
    }
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _serviceSubscription?.cancel();
    super.dispose();
  }

  Future<void> _abortNavigation() async {
    _stopwatchTimer?.cancel();
    _serviceSubscription?.cancel();
    FlutterBackgroundService().invoke("stopService");
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_recording');
    await prefs.remove('start_time');
    
    if (mounted) Navigator.pop(context);
  }

  void _reconnectServiceListener() {
    final service = FlutterBackgroundService();
    _serviceSubscription = service.on('update').listen((event) async {
      if (event != null && mounted && !_isPaused) {
        double speed = event['speed'] ?? 0.0;
        double alt = event['altitude'] ?? 0.0;
        double lat = event['lat'] ?? 0.0;
        double lng = event['lng'] ?? 0.0;
        mt.LatLng currentLoc = mt.LatLng(lat, lng);

        setState(() {
          _elevation = alt.toStringAsFixed(0);
          if (speed > 0.5) { 
            double paceMinPerKm = (60 / (speed * 3.6));
            int pMin = paceMinPerKm.floor();
            int pSec = ((paceMinPerKm - pMin) * 60).round();
            _pace = "$pMin:${pSec.toString().padLeft(2, '0')}";
          }
        });

        _actualRecordedPoints.add(currentLoc);

        if (_actualRecordedPoints.length > 1 && _mapController != null) {
          try {
            await _mapController!.setGeoJsonSource("walked-source", {
              "type": "FeatureCollection",
              "features": [{"type": "Feature", "geometry": {"type": "LineString", "coordinates": _actualRecordedPoints.map((p) => [p.longitude, p.latitude]).toList()}}]
            });
          } catch (_) {}
        }

        if (_routeGeometryPoints.isNotEmpty) {
          bool isOnRoute = mt.PolygonUtil.isLocationOnPath(currentLoc, _routeGeometryPoints, false, tolerance: 40.0);
          
          if (!isOnRoute && !_isOffRoute) {
            setState(() => _isOffRoute = true);
            _stopwatchTimer?.cancel(); 
            Vibration.vibrate(pattern: [500, 1000, 500, 1000]); 
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Off Route! Tracking paused.'), backgroundColor: Colors.redAccent, duration: Duration(seconds: 3)));
          } else if (isOnRoute && _isOffRoute) {
            setState(() => _isOffRoute = false);
            _startStopwatch(); 
            Vibration.vibrate(duration: 200);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Back on route! Resumed.'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
          }

          final endPoint = _routeGeometryPoints.last;
          final distToEnd = mt.SphericalUtil.computeDistanceBetween(currentLoc, endPoint);
          if (distToEnd < 15.0 && _isRecording && !_isPaused) {
            setState(() { _isPaused = true; _isHudExpanded = true; });
            _stopwatchTimer?.cancel();
            Vibration.vibrate(pattern: [300, 150, 300]);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Destination reached!'), backgroundColor: neonAccent, duration: Duration(seconds: 4)));
          }
        }
      }
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    _recenterMap();
  }

  Future<Uint8List> _generateIconBytes(IconData icon, Color color) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: 100.0, fontFamily: icon.fontFamily, package: icon.fontPackage, color: color));
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0.0, 0.0));
    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(textPainter.width.toInt(), textPainter.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _generate3DPinIcon(Color color, IconData iconData) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const double width = 120.0;
    const double height = 180.0; 

    final baseRect = Rect.fromCenter(center: const Offset(width / 2, height - 15), width: 70, height: 25);
    canvas.drawOval(baseRect, Paint()..color = color.withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawOval(baseRect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);

    final beamPath = Path()
      ..moveTo(width / 2 - 3, 50)
      ..lineTo(width / 2 + 3, 50)
      ..lineTo(width / 2 + 10, height - 15)
      ..lineTo(width / 2 - 10, height - 15)
      ..close();
    canvas.drawPath(beamPath, Paint()..shader = ui.Gradient.linear(const Offset(0, 50), const Offset(0, height), [color.withOpacity(0.8), color.withOpacity(0.0)]));

    canvas.drawCircle(const Offset(width / 2, 50), 38, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(width / 2, 50), 32, Paint()..color = color);
    canvas.drawCircle(const Offset(width / 2, 50), 28, Paint()..color = const Color(0xFF161922)); 

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(fontSize: 34.0, fontFamily: iconData.fontFamily, package: iconData.fontPackage, color: Colors.white),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((width - textPainter.width) / 2, 50 - (textPainter.height / 2)));

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _onStyleLoaded() async {
    if (_mapController == null) return;
    
    List<List<double>> coords = _routeGeometryPoints.map((p) => [p.longitude, p.latitude]).toList();
    final routeGeoJson = {
      "type": "FeatureCollection",
      "features": [{"type": "Feature", "properties": {}, "geometry": {"type": "LineString", "coordinates": coords}}]
    };

    try {
      await _mapController!.addSource("trek-source", GeojsonSourceProperties(data: routeGeoJson));
      await _mapController!.addLineLayer("trek-source", "trek-casing", const LineLayerProperties(lineColor: "#FFFFFF", lineWidth: 36.0, lineCap: "round", lineJoin: "round"));
      await _mapController!.addLineLayer("trek-source", "trek-layer", const LineLayerProperties(lineColor: "#888888", lineWidth: 24.0, lineCap: "round", lineJoin: "round"));

      try {
        final Uint8List arrowBytes = await _generateIconBytes(Icons.keyboard_double_arrow_right_rounded, Colors.white70);
        await _mapController!.addImage("route-arrow", arrowBytes);
        await _mapController!.addSymbolLayer("trek-source", "trek-arrows", const SymbolLayerProperties(
          symbolPlacement: "line", symbolSpacing: 90.0, iconImage: "route-arrow", iconSize: 0.6, iconAllowOverlap: true,
        ));
      } catch (_) {}

      await _mapController!.addSource("walked-source", const GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": []}));
      await _mapController!.addLineLayer("walked-source", "walked-glow", const LineLayerProperties(lineColor: "#D4FF00", lineWidth: 48.0, lineOpacity: 0.4, lineBlur: 8.0, lineCap: "round", lineJoin: "round"));
      await _mapController!.addLineLayer("walked-source", "walked-layer", const LineLayerProperties(lineColor: "#AADD00", lineWidth: 24.0, lineCap: "round", lineJoin: "round"));

      if (_routeGeometryPoints.isNotEmpty) {
        final start = _routeGeometryPoints.first;
        final end = _routeGeometryPoints.last;

        try {
          final Uint8List start3DPin = await _generate3DPinIcon(const Color(0xFF0088FF), Icons.play_arrow_rounded);
          await _mapController!.addImage("start-3d-pin", start3DPin);
          
          final Uint8List end3DPin = await _generate3DPinIcon(const Color(0xFFFF0044), Icons.flag_rounded);
          await _mapController!.addImage("end-3d-pin", end3DPin);
        } catch (_) {}

        await _mapController!.addSource("start-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [start.longitude, start.latitude]}}]}));
        await _mapController!.addSymbolLayer("start-source", "start-layer", const SymbolLayerProperties(
          iconImage: "start-3d-pin", iconSize: 0.8, iconAnchor: "bottom", iconAllowOverlap: true
        ));

        await _mapController!.addSource("end-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [end.longitude, end.latitude]}}]}));
        await _mapController!.addSymbolLayer("end-source", "end-layer", const SymbolLayerProperties(
          iconImage: "end-3d-pin", iconSize: 0.8, iconAnchor: "bottom", iconAllowOverlap: true
        ));
      }
    } catch (e) {
      debugPrint("Error drawing route: $e");
    }
  }

  void _recenterMap() async {
    if (_mapController != null) {
      _mapController!.updateMyLocationTrackingMode(MyLocationTrackingMode.trackingCompass);
      try {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 19.5, 
              tilt: 75.0, 
            )
          ),
          duration: const Duration(milliseconds: 800)
        );
      } catch (_) {}
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
    final prefs = await SharedPreferences.getInstance();
    if (!_isRecording) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      }

      await prefs.setBool('is_recording', true);
      await prefs.setInt('start_time', DateTime.now().millisecondsSinceEpoch);

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _isHudExpanded = true; 
        _mapController?.updateMyLocationTrackingMode(MyLocationTrackingMode.trackingCompass);
      });
      _recenterMap(); 

      final service = FlutterBackgroundService();
      await service.startService();
      _startStopwatch();
      _reconnectServiceListener();
    } else if (_isRecording && !_isPaused) {
      setState(() => _isPaused = true);
      _stopwatchTimer?.cancel();
    } else if (_isRecording && _isPaused) {
      setState(() => _isPaused = false);
      _startStopwatch();
    }
  }

  Future<void> _finishTrek() async {
    _stopwatchTimer?.cancel();
    _serviceSubscription?.cancel();
    FlutterBackgroundService().invoke("stopService");

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_recording');
    await prefs.remove('start_time');

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saving trek data...'), duration: Duration(seconds: 1)));

    try {
      final List<Map<String, double>> routeJson = _actualRecordedPoints.map((point) => {'lat': point.latitude, 'lng': point.longitude}).toList();
      final myId = Supabase.instance.client.auth.currentUser!.id;

      await Supabase.instance.client.from('completed_treks').insert({
        'user_id': myId,
        'trek_name': widget.trekToFollow['name'] ?? 'Guided Trek',
        'distance': _distance,
        'duration': _elapsedTime,
        'pace': _pace,
        'elevation_gain': _elevation,
        'recorded_route': routeJson,
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trek Finished & Saved!'), backgroundColor: Colors.green));
      
      if (mounted) Navigator.pop(context);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save trek: $e'), backgroundColor: Colors.red));
    }
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
              initialCameraPosition: const CameraPosition(
                target: LatLng(12.2958, 76.6394), 
                zoom: 19.5, 
                tilt: 75.0 
              ),
              myLocationEnabled: true,
              myLocationRenderMode: MyLocationRenderMode.compass, 
              myLocationTrackingMode: MyLocationTrackingMode.trackingCompass,
              compassEnabled: false, 
            ),
          ),
          
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16, right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _abortNavigation,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                    child: const Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: _isOffRoute ? Colors.redAccent.withOpacity(0.9) : Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isOffRoute ? Colors.red : Colors.white10)),
                  child: Row(
                    children: [
                      Icon(_isOffRoute ? Icons.warning_amber_rounded : Icons.navigation, color: _isOffRoute ? Colors.white : neonAccent, size: 16),
                      const SizedBox(width: 8),
                      Text(_isOffRoute ? 'OFF ROUTE!' : 'Navigating', style: TextStyle(color: _isOffRoute ? Colors.white : neonAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 48), 
              ],
            ),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FloatingActionButton(heroTag: 'layers_nav_btn', backgroundColor: cardSurface, mini: true, onPressed: _showMapStyleSelector, child: const Icon(Icons.layers, color: Colors.white)),
                      const SizedBox(height: 12),
                      FloatingActionButton(heroTag: 'recenter_nav', backgroundColor: cardSurface, mini: true, onPressed: _recenterMap, child: const Icon(Icons.my_location, color: neonAccent)),
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
                            child: Container(
                              color: Colors.transparent, 
                              width: double.infinity,
                              padding: const EdgeInsets.only(top: 16, bottom: 8),
                              child: Column(
                                children: [
                                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(height: 16),
                                  Text(_elapsedTime, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
                              if (_isRecording && _isHudExpanded)
                                Column(
                                  children: [
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildStatColumn(_distance, 'km', 'DIST'),
                                        Container(height: 40, width: 1, color: Colors.white10),
                                        _buildStatColumn(_pace, '/km', 'PACE'),
                                      ],
                                    ),
                                    const SizedBox(height: 32),
                                  ],
                                ),
                              if (!_isRecording)
                                Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity, height: 56,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                                        onPressed: _toggleTracking,
                                        icon: const Icon(Icons.play_arrow, size: 28),
                                        label: const Text('START NAVIGATION', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity, height: 48,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: neonAccent, 
                                          side: const BorderSide(color: neonAccent),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))
                                        ),
                                        onPressed: _toggleReverse,
                                        icon: const Icon(Icons.swap_vert, size: 20),
                                        label: const Text('REVERSE DIRECTION', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                      ),
                                    ),
                                  ],
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
                                          label: Text(_isPaused ? 'RESUME' : 'PAUSE', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ),
                                    if (_isPaused) ...[
                                      const SizedBox(width: 16),
                                      Expanded(child: HoldToFinishButton(onComplete: _finishTrek)),
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
          crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
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

class HoldToFinishButton extends StatefulWidget {
  final VoidCallback onComplete;
  const HoldToFinishButton({super.key, required this.onComplete});

  @override
  State<HoldToFinishButton> createState() => _HoldToFinishButtonState();
}

class _HoldToFinishButtonState extends State<HoldToFinishButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _controller.addListener(() {
      setState(() {}); 
      if (_controller.isCompleted && !_isCompleted) {
        _isCompleted = true; Vibration.vibrate(duration: 100); widget.onComplete();
      }
    });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { if (!_isCompleted) _controller.forward(); },
      onTapUp: (_) { if (!_isCompleted) _controller.reverse(); },
      onTapCancel: () { if (!_isCompleted) _controller.reverse(); },
      child: Container(
        height: 56, width: double.infinity,
        decoration: BoxDecoration(color: Colors.red[900], borderRadius: BorderRadius.circular(100)),
        child: Stack(
          children: [
            FractionallySizedBox(widthFactor: _controller.value, child: Container(decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(100)))),
            Center(child: Text(_controller.isAnimating ? 'KEEP HOLDING...' : 'FINISH', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1))),
          ],
        ),
      ),
    );
  }
}