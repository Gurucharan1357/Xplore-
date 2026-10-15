import 'dart:async';
import 'dart:convert';
import 'dart:typed_data'; 
import 'dart:ui' as ui;
import 'dart:io';   
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;
import 'package:vibration/vibration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

String get MAPBOX_ACCESS_TOKEN => dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

const String styleDark = 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';
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
  List<mt.LatLng> _actualRecordedPoints = []; 
  
  bool _isOffRoute = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _restoreRecordingState();
  }

  @override
  void didUpdateWidget(RecordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trekToFollow != oldWidget.trekToFollow && widget.trekToFollow != null) {
      Future.delayed(const Duration(milliseconds: 300), () => _drawTrekRoute());
    }
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _serviceSubscription?.cancel();
    super.dispose();
  }

  Future<void> _restoreRecordingState() async {
    final prefs = await SharedPreferences.getInstance();
    final isRec = prefs.getBool('is_recording') ?? false;
    
    if (isRec) {
      final startTime = prefs.getInt('start_time') ?? DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _isRecording = true;
        _isHudExpanded = true;
        RecordScreen.isNavHidden.value = true;
        _elapsedSeconds = (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000;
      });
      _startStopwatch();
      _reconnectServiceListener();
    }
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
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Off Route! Tracking paused until you return.'), backgroundColor: Colors.redAccent, duration: Duration(seconds: 3)));
          } 
          else if (isOnRoute && _isOffRoute) {
            setState(() => _isOffRoute = false);
            _startStopwatch(); 
            Vibration.vibrate(duration: 200);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Back on route! Tracking resumed.'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
          }

          final endPoint = _routeGeometryPoints.last;
          final distToEnd = mt.SphericalUtil.computeDistanceBetween(currentLoc, endPoint);
          if (distToEnd < 15.0 && _isRecording && !_isPaused) {
            setState(() { _isPaused = true; _isHudExpanded = true; });
            _stopwatchTimer?.cancel();
            Vibration.vibrate(pattern: [300, 150, 300]);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Destination reached! Hold Finish to save.'), backgroundColor: neonAccent, duration: Duration(seconds: 4)));
          }
        }
      }
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    _recenterMap();
  }

  void _onStyleLoaded() async {
    if (_mapController == null) return;
    
    try {
      await _mapController!.addSource("walked-source", const GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": []}));
      await _mapController!.addLineLayer("walked-source", "walked-glow", const LineLayerProperties(lineColor: "#D4FF00", lineWidth: 14.0, lineOpacity: 0.4, lineBlur: 4.0, lineCap: "round", lineJoin: "round"));
      await _mapController!.addLineLayer("walked-source", "walked-layer", const LineLayerProperties(lineColor: "#AADD00", lineWidth: 6.0, lineCap: "round", lineJoin: "round"));
    } catch (e) {
      debugPrint("Error initializing walked layer: $e");
    }

    if (widget.trekToFollow != null) {
      _drawTrekRoute();
    }
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

  Future<void> _drawTrekRoute() async {
    if (widget.trekToFollow == null || _mapController == null) return;
    dynamic geojsonData = widget.trekToFollow!['route_geom'];
    if (geojsonData == null) return;

    if (geojsonData is String) try { geojsonData = jsonDecode(geojsonData); } catch (_) { return; }
    if (geojsonData is Map<String, dynamic> && geojsonData['coordinates'] != null) {
      _routeGeometryPoints.clear();
      for (var coord in geojsonData['coordinates']) { _routeGeometryPoints.add(mt.LatLng(coord[1], coord[0])); }
    }
    if (geojsonData is Map<String, dynamic> && geojsonData['type'] == 'LineString') {
      geojsonData = {"type": "FeatureCollection", "features": [{"type": "Feature","properties": {},"geometry": geojsonData}]};
    }

    try {
      try { await _mapController!.removeLayer("trek-arrows"); } catch (_) {} 
      try { await _mapController!.removeLayer("trek-layer"); } catch (_) {}
      try { await _mapController!.removeLayer("trek-casing"); } catch (_) {}
      try { await _mapController!.removeSource("trek-source"); } catch (_) {}
      
      final markerLayers = ['start-glow', 'start-border', 'start-core', 'end-glow', 'end-border', 'end-core'];
      for (var layer in markerLayers) { try { await _mapController!.removeLayer(layer); } catch (_) {} }
      try { await _mapController!.removeSource("start-source"); } catch (_) {}
      try { await _mapController!.removeSource("end-source"); } catch (_) {}

      await _mapController!.addSource("trek-source", GeojsonSourceProperties(data: geojsonData));
      await _mapController!.addLineLayer("trek-source", "trek-casing", const LineLayerProperties(lineColor: "#FFFFFF", lineWidth: 10.0, lineCap: "round", lineJoin: "round"));
      await _mapController!.addLineLayer("trek-source", "trek-layer", const LineLayerProperties(lineColor: "#888888", lineWidth: 6.0, lineCap: "round", lineJoin: "round"));

      try {
        final Uint8List arrowBytes = await _generateIconBytes(Icons.chevron_right_rounded, Colors.white70);
        await _mapController!.addImage("route-arrow", arrowBytes);
        await _mapController!.addSymbolLayer("trek-source", "trek-arrows", const SymbolLayerProperties(symbolPlacement: "line", symbolSpacing: 75.0, iconImage: "route-arrow", iconSize: 0.35, iconAllowOverlap: true, iconIgnorePlacement: false));
      } catch (_) {}

      if (_routeGeometryPoints.isNotEmpty) {
        final start = _routeGeometryPoints.first;
        final end = _routeGeometryPoints.last;

        await _mapController!.addSource("start-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [start.longitude, start.latitude]}}]}));
        await _mapController!.addCircleLayer("start-source", "start-glow", const CircleLayerProperties(circleRadius: 18.0, circleColor: "#0088FF", circleOpacity: 0.3, circleBlur: 0.5));
        await _mapController!.addCircleLayer("start-source", "start-border", const CircleLayerProperties(circleRadius: 8.0, circleColor: "#FFFFFF"));
        await _mapController!.addCircleLayer("start-source", "start-core", const CircleLayerProperties(circleRadius: 5.0, circleColor: "#00BFFF"));

        await _mapController!.addSource("end-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [end.longitude, end.latitude]}}]}));
        await _mapController!.addCircleLayer("end-source", "end-glow", const CircleLayerProperties(circleRadius: 18.0, circleColor: "#FF0044", circleOpacity: 0.3, circleBlur: 0.5));
        await _mapController!.addCircleLayer("end-source", "end-border", const CircleLayerProperties(circleRadius: 8.0, circleColor: "#FFFFFF"));
        await _mapController!.addCircleLayer("end-source", "end-core", const CircleLayerProperties(circleRadius: 5.0, circleColor: "#FF3366"));
      }

      _mapController!.animateCamera(CameraUpdate.zoomTo(14.0));
    } catch (e) {
      debugPrint("Error drawing route: $e");
    }
  }

  void _recenterMap() async {
    if (_mapController != null) {
      _mapController!.updateMyLocationTrackingMode(MyLocationTrackingMode.trackingCompass);
      try {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 16.5));
      } catch (e) { debugPrint("Error recentering map: $e"); }
    }
  }

  void _resetCompass() {
    if (_mapController != null) _mapController!.animateCamera(CameraUpdate.bearingTo(0.0));
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
        RecordScreen.isNavHidden.value = true; 
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

  Future<void> _cleanupRecordingState() async {
    _stopwatchTimer?.cancel();
    _serviceSubscription?.cancel();
    FlutterBackgroundService().invoke("stopService");

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_recording');
    await prefs.remove('start_time');

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
      _actualRecordedPoints.clear();
    });

    try {
      await _mapController!.setGeoJsonSource("walked-source", const {"type": "FeatureCollection", "features": []});
    } catch (_) {}

    _mapController?.animateCamera(CameraUpdate.tiltTo(0.0));
    _mapController?.animateCamera(CameraUpdate.zoomTo(14.0));
  }

  void _discardTrek() async {
    await _cleanupRecordingState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trail discarded.'), backgroundColor: Colors.grey));
    }
  }

  void _showFinishSheet() {
    setState(() => _isPaused = true);
    _stopwatchTimer?.cancel();
    
    final nameCtrl = TextEditingController(text: widget.trekToFollow?['name'] ?? 'Freestyle Walk');
    final descCtrl = TextEditingController();
    File? selectedImage;
    _isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardSurface,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickImage() async {
            final picker = ImagePicker();
            final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
            if (pickedFile != null) {
              setSheetState(() => selectedImage = File(pickedFile.path));
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Finish Trek', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  
                  const Text('Trail Name', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true, fillColor: bgColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Description', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'How was the trail? Trail conditions, scenery...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true, fillColor: bgColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: pickImage,
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        image: selectedImage != null ? DecorationImage(image: FileImage(selectedImage!), fit: BoxFit.cover) : null,
                      ),
                      child: selectedImage == null 
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, color: neonAccent, size: 32),
                              SizedBox(height: 8),
                              Text('Add Cover Photo', style: TextStyle(color: neonAccent, fontWeight: FontWeight.bold)),
                            ],
                          )
                        : Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                  onPressed: () => setSheetState(() => selectedImage = null),
                                ),
                              ),
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent.withOpacity(0.2), 
                            foregroundColor: Colors.blueAccent, 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            side: const BorderSide(color: Colors.blueAccent)
                          ),
                          onPressed: _isSaving ? null : () => _processSave(ctx, setSheetState, nameCtrl.text.trim(), descCtrl.text.trim(), selectedImage, false),
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Private'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: neonAccent, 
                            foregroundColor: Colors.black, 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0
                          ),
                          onPressed: _isSaving ? null : () => _processSave(ctx, setSheetState, nameCtrl.text.trim(), descCtrl.text.trim(), selectedImage, true),
                          icon: const Icon(Icons.public),
                          label: const Text('Public', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  Center(
                    child: TextButton.icon(
                      onPressed: _isSaving ? null : () {
                        Navigator.pop(ctx);
                        _discardTrek();
                      }, 
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      label: const Text('Discard Trail', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        }
      )
    );
  }

  Future<void> _processSave(BuildContext sheetCtx, void Function(void Function()) setSheetState, String name, String description, File? imageFile, bool isPublic) async {
    setSheetState(() => _isSaving = true); 
    try {
      String? imageUrl;
      final myId = Supabase.instance.client.auth.currentUser!.id;

      if (imageFile != null) {
        final ext = imageFile.path.split('.').last.toLowerCase();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$myId.$ext';
        await Supabase.instance.client.storage.from('TrailImages').upload(fileName, imageFile);
        imageUrl = Supabase.instance.client.storage.from('TrailImages').getPublicUrl(fileName);
      }

      final List<Map<String, double>> routeJson = _actualRecordedPoints.map((point) => {'lat': point.latitude, 'lng': point.longitude}).toList();

      await Supabase.instance.client.from('completed_treks').insert({
        'user_id': myId,
        'trek_name': name.isEmpty ? 'Freestyle Walk' : name,
        'description': description,
        'image_url': imageUrl,
        'distance': _distance,
        'duration': _elapsedTime,
        'pace': _pace,
        'elevation_gain': _elevation,
        'recorded_route': routeJson,
        'is_public': isPublic, 
      });

      if (mounted) {
        Navigator.pop(sheetCtx);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isPublic ? 'Trail published to Explore!' : 'Saved to your Private Profile!'), backgroundColor: Colors.green));
      }
      await _cleanupRecordingState();
    } catch (e) {
      debugPrint("Error saving trek: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save trek: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setSheetState(() => _isSaving = false); 
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
              initialCameraPosition: const CameraPosition(target: LatLng(12.2958, 76.6394), zoom: 15.0),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                                        child: HoldToFinishButton(onComplete: _showFinishSheet),
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
        _isCompleted = true;
        Vibration.vibrate(duration: 100); 
        widget.onComplete();
        _controller.reverse(); 
        _isCompleted = false; 
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
            FractionallySizedBox(
              widthFactor: _controller.value,
              child: Container(decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(100))),
            ),
            Center(child: Text(_controller.isAnimating ? 'KEEP HOLDING...' : 'HOLD TO FINISH', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1))),
          ],
        ),
      ),
    );
  }
}