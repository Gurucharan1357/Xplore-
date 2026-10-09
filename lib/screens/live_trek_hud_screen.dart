import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:xplore_mobile/utils/offline_sync_manager.dart';
import 'package:xplore_mobile/main.dart'; 
import 'package:xplore_mobile/screens/my_dashboard_screen.dart'; // <--- Linked to AppSettings!

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class LiveTrekHudScreen extends StatefulWidget {
  final Map<String, dynamic>? trekToFollow;
  const LiveTrekHudScreen({super.key, this.trekToFollow});

  @override
  State<LiveTrekHudScreen> createState() => _LiveTrekHudScreenState();
}

class _LiveTrekHudScreenState extends State<LiveTrekHudScreen> with SingleTickerProviderStateMixin {
  bool isPaused = false;
  bool _isTracking = false;
  bool _isCameraLocked = true;

  // GPS & Tracking State
  MapLibreMapController? mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSub;
  
  double _liveDistanceKm = 0.0;
  double _liveElevationGain = 0.0;
  final List<LatLng> _liveRoutePoints = [];
  final List<Position> _offlineTrekData = [];
  final List<Map<String, dynamic>> _waypoints = [];
  final List<LatLng> _guidedTrekPoints = [];
  
  Circle? _currentPuck;
  Line? _routeLine;
  Line? _routeBorder;
  Line? _guideLine;
  Circle? _guidePuck;
  bool _isAddingPuck = false;

  // Auto-pause variables
  bool _isAutoPaused = false;
  Timer? _stopTimer;
  final double _stopSpeedThresholdMs = 0.22;
  final int _stopDurationSeconds = 12;

  // Custom Bottom Sheet Layout States
  double _activeSheetHeight = 0.0;
  Widget? _activeSheetContent;
  bool _isDownloadingMap = false; 
  double _downloadProgress = 0.0;

  // Turn-By-Turn Navigation States
  bool _isOffRoute = false;
  int _closestGuideIndex = 0;
  double _distanceToNextManeuver = 0.0;
  String _maneuverInstruction = "Continue along trail";
  IconData _maneuverIcon = Icons.straight;
  double _remainingGuideDistanceM = 0.0;

  // Timing
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void didUpdateWidget(covariant LiveTrekHudScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trekToFollow != null && widget.trekToFollow != oldWidget.trekToFollow) {
      _loadGuidedTrek(widget.trekToFollow!);
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _ticker?.cancel();
    _stopTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  void _showInlineSheet(Widget content, double height) {
    setState(() { _activeSheetContent = content; _activeSheetHeight = height; });
  }

  void _hideInlineSheet() {
    setState(() { _activeSheetHeight = 0.0; Future.delayed(const Duration(milliseconds: 250), () { if (_activeSheetHeight == 0 && mounted) setState(() => _activeSheetContent = null); }); });
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;
    await _fetchInitialPosition();
    if (_positionStreamSub == null) _startLocationUpdates();
  }

  Future<void> _fetchInitialPosition() async {
    try {
      final initialPosition = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() => _currentPosition = initialPosition);
      if (mapController != null && !AppSettings.amoledMode.value) {
        _updatePucksOnMap(initialPosition);
        mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(initialPosition.latitude, initialPosition.longitude), 16.0));
      }
    } catch (_) {}
  }

  double _calculateBearing(LatLng p1, LatLng p2) {
    final lat1 = p1.latitude * math.pi / 180; final lon1 = p1.longitude * math.pi / 180;
    final lat2 = p2.latitude * math.pi / 180; final lon2 = p2.longitude * math.pi / 180;
    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final radians = math.atan2(y, x);
    return (radians * 180 / math.pi + 360) % 360;
  }

  void _calculateTurnByTurn(Position pos) {
    if (_guidedTrekPoints.length < 2) return;
    int closestIdx = 0; double minDistance = double.infinity;
    for (int i = 0; i < _guidedTrekPoints.length; i++) {
      final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, _guidedTrekPoints[i].latitude, _guidedTrekPoints[i].longitude);
      if (d < minDistance) { minDistance = d; closestIdx = i; }
    }
    _closestGuideIndex = closestIdx;
    double remaining = 0.0;
    for (int i = closestIdx; i < _guidedTrekPoints.length - 1; i++) {
      remaining += Geolocator.distanceBetween(_guidedTrekPoints[i].latitude, _guidedTrekPoints[i].longitude, _guidedTrekPoints[i + 1].latitude, _guidedTrekPoints[i + 1].longitude);
    }
    _remainingGuideDistanceM = remaining;

    if (closestIdx >= _guidedTrekPoints.length - 2 || remaining < 25.0) {
      setState(() { _maneuverIcon = Icons.flag_rounded; _distanceToNextManeuver = remaining; _maneuverInstruction = "Destination reached!"; }); return;
    }

    double distToTurn = 0.0; IconData detectedIcon = Icons.straight; String detectedText = "Continue straight on trail"; bool turnFound = false;
    for (int i = closestIdx; i < _guidedTrekPoints.length - 2; i++) {
      distToTurn += Geolocator.distanceBetween(_guidedTrekPoints[i].latitude, _guidedTrekPoints[i].longitude, _guidedTrekPoints[i + 1].latitude, _guidedTrekPoints[i + 1].longitude);
      final bearingCurrent = _calculateBearing(_guidedTrekPoints[i], _guidedTrekPoints[i + 1]);
      final bearingNext = _calculateBearing(_guidedTrekPoints[i + 1], _guidedTrekPoints[i + 2]);
      double diff = (bearingNext - bearingCurrent + 540) % 360 - 180;
      if (diff.abs() > 35) {
        turnFound = true;
        if (diff > 65) { detectedIcon = Icons.turn_sharp_right; detectedText = "Sharp right bend"; } 
        else if (diff > 35) { detectedIcon = Icons.turn_right; detectedText = "Turn right ahead"; } 
        else if (diff < -65) { detectedIcon = Icons.turn_sharp_left; detectedText = "Sharp left bend"; } 
        else { detectedIcon = Icons.turn_left; detectedText = "Turn left ahead"; }
        break;
      }
      if (distToTurn > 1500) break;
    }
    setState(() { _distanceToNextManeuver = turnFound ? distToTurn : remaining; _maneuverIcon = turnFound ? detectedIcon : Icons.straight; _maneuverInstruction = turnFound ? detectedText : "Follow trail to destination"; });
  }

  void _startLocationUpdates() {
    late LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(accuracy: LocationAccuracy.best, distanceFilter: 3, foregroundNotificationConfig: const ForegroundNotificationConfig(notificationText: "Live tracking active", notificationTitle: "Xplore", enableWakeLock: true));
    } else {
      locationSettings = const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
    }

    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) {
      setState(() => _currentPosition = pos);
      
      if (_isTracking && !isPaused) {
        if (pos.accuracy > 18.0) return;
        
        // --- LINKED AUTO-PAUSE SETTING ---
        if (AppSettings.autoPause.value && pos.speed < _stopSpeedThresholdMs) {
          if (_stopTimer == null && !_isAutoPaused) {
            _stopTimer = Timer(Duration(seconds: _stopDurationSeconds), () {
              setState(() { _isAutoPaused = true; _stopwatch.stop(); HapticFeedback.lightImpact(); });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auto-Paused. Walk to resume.'), duration: Duration(seconds: 2)));
            });
          }
        } else {
          _stopTimer?.cancel(); _stopTimer = null;
          if (_isAutoPaused) {
            setState(() { _isAutoPaused = false; _stopwatch.start(); HapticFeedback.mediumImpact(); });
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auto-Resumed!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
          }
        }

        if (!_isAutoPaused) {
          _offlineTrekData.add(pos);
          OfflineSyncManager.autoSaveLiveTrek(_offlineTrekData);
          _liveRoutePoints.add(LatLng(pos.latitude, pos.longitude));
          _liveDistanceKm = _calculateTotalDistance() / 1000;
          _liveElevationGain = _calculateTotalElevationGain();
          if (!AppSettings.amoledMode.value) _updateLiveRoute();

          if (_guidedTrekPoints.isNotEmpty) {
            _calculateTurnByTurn(pos);
            double distFromPath = Geolocator.distanceBetween(pos.latitude, pos.longitude, _guidedTrekPoints[_closestGuideIndex].latitude, _guidedTrekPoints[_closestGuideIndex].longitude);
            bool currentlyOffRoute = distFromPath > 40.0;
            if (currentlyOffRoute && !_isOffRoute) HapticFeedback.heavyImpact(); 
            setState(() => _isOffRoute = currentlyOffRoute);
          }
        }
      }
      
      if (!AppSettings.amoledMode.value) {
        _updatePucksOnMap(pos);
        if (_isCameraLocked && mapController != null) {
          mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 17.5, bearing: pos.heading >= 0 ? pos.heading : 0.0, tilt: 45.0)));
        }
      }
    });
  }

  double _calculateTotalDistance() {
    if (_offlineTrekData.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < _offlineTrekData.length - 1; i++) {
      total += Geolocator.distanceBetween(_offlineTrekData[i].latitude, _offlineTrekData[i].longitude, _offlineTrekData[i + 1].latitude, _offlineTrekData[i + 1].longitude);
    }
    return total;
  }

  double _calculateTotalElevationGain() {
    if (_offlineTrekData.length < 2) return 0.0;
    double gain = 0.0;
    for (int i = 1; i < _offlineTrekData.length; i++) {
      double diff = _offlineTrekData[i].altitude - _offlineTrekData[i - 1].altitude;
      if (diff > 0.5) gain += diff;
    }
    return gain;
  }

  Future<void> _updateLiveRoute() async {
    if (mapController == null || _liveRoutePoints.length < 2) return;
    if (_routeBorder == null || _routeLine == null) {
      _routeBorder = await mapController!.addLine(LineOptions(geometry: _liveRoutePoints, lineColor: '#FFFFFF', lineWidth: 5.0, lineJoin: 'round'));
      _routeLine = await mapController!.addLine(LineOptions(geometry: _liveRoutePoints, lineColor: '#D4FF00', lineWidth: 3.0, lineJoin: 'round'));
    } else {
      await mapController!.updateLine(_routeBorder!, LineOptions(geometry: _liveRoutePoints));
      await mapController!.updateLine(_routeLine!, LineOptions(geometry: _liveRoutePoints));
    }
  }

  Future<void> _loadGuidedTrek(Map<String, dynamic> trek) async {
    try {
      List<LatLng> pts = [];
      final routeData = trek['route_geojson'] ?? trek['route_geom'];
      if (routeData == null) return;

      if (routeData is String) {
        if (routeData.contains('LINESTRING')) {
          final cleaned = routeData.replaceAll(RegExp(r'SRID=\d+;'), '').replaceAll('LINESTRING(', '').replaceAll(')', '');
          final pairs = cleaned.split(',');
          for (var pair in pairs) {
            final coords = pair.trim().split(RegExp(r'\s+'));
            if (coords.length >= 2) {
              final lon = double.tryParse(coords[0]);
              final lat = double.tryParse(coords[1]);
              if (lon != null && lat != null) pts.add(LatLng(lat, lon));
            }
          }
        } else {
          final decoded = jsonDecode(routeData);
          final coordinates = decoded['coordinates'] ?? decoded['geometry']?['coordinates'] ?? [];
          pts = coordinates.map<LatLng>((c) => LatLng(c[1] as double, c[0] as double)).toList();
        }
      } else if (routeData is Map) {
        final coordinates = routeData['coordinates'] ?? routeData['geometry']?['coordinates'] ?? [];
        pts = coordinates.map<LatLng>((c) => LatLng(c[1] as double, c[0] as double)).toList();
      }

      _guidedTrekPoints.clear();
      _guidedTrekPoints.addAll(pts);

      if (mapController != null && _guidedTrekPoints.isNotEmpty && !AppSettings.amoledMode.value) {
        if (_guideLine != null) await mapController!.removeLine(_guideLine!);
        if (_guidePuck != null) await mapController!.removeCircle(_guidePuck!);
        _guideLine = await mapController!.addLine(LineOptions(geometry: _guidedTrekPoints, lineColor: '#1A237E', lineWidth: 8.0, lineOpacity: 0.4, lineJoin: 'round'));
        _guidePuck = await mapController!.addCircle(CircleOptions(geometry: _guidedTrekPoints.first, circleRadius: 9.0, circleColor: '#00E5FF', circleStrokeWidth: 3.0, circleStrokeColor: '#FFFFFF'));
        mapController!.animateCamera(CameraUpdate.newLatLngZoom(_guidedTrekPoints.first, 16.0));
      }
    } catch (e) {
      debugPrint('❌ Error loading guided trek: $e');
    }
  }

  Future<void> _updatePucksOnMap(Position position) async {
    if (mapController == null) return;
    final currentLatLng = LatLng(position.latitude, position.longitude);

    if (_currentPuck == null) {
      if (_isAddingPuck) return;
      _isAddingPuck = true;
      try {
        _currentPuck = await mapController!.addCircle(CircleOptions(geometry: currentLatLng, circleRadius: 8.0, circleColor: '#007AFF', circleStrokeWidth: 3.0, circleStrokeColor: '#FFFFFF'));
      } finally { _isAddingPuck = false; }
    } else {
      await mapController!.updateCircle(_currentPuck!, CircleOptions(geometry: currentLatLng));
    }
  }

  Future<void> _clearMapData() async {
    OfflineSyncManager.clearUnfinishedTrek();
    _liveRoutePoints.clear(); _offlineTrekData.clear(); _guidedTrekPoints.clear(); _waypoints.clear();
    _liveDistanceKm = 0.0; _liveElevationGain = 0.0; _isOffRoute = false; _isAutoPaused = false;
    _stopTimer?.cancel(); _stopTimer = null;
    if (mapController != null) {
      await mapController!.clearCircles(); await mapController!.clearLines();
      _guidePuck = null; _routeLine = null; _routeBorder = null; _guideLine = null; _currentPuck = null; _isAddingPuck = false;
    }
    if (_currentPosition != null && !AppSettings.amoledMode.value) _updatePucksOnMap(_currentPosition!);
    if (mounted) setState(() {});
  }

  void _startTrek() {
    setState(() { _isTracking = true; isPaused = false; _isAutoPaused = false; _liveDistanceKm = 0.0; _liveElevationGain = 0.0; _isOffRoute = false; _isCameraLocked = true; _stopwatch.reset(); _stopwatch.start(); });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    
    if (AppSettings.backgroundTracking.value) {
      FlutterBackgroundService().startService();
    }
    
    if (widget.trekToFollow == null) _clearMapData();
    else if (_currentPosition != null) _calculateTurnByTurn(_currentPosition!);
  }

  void _pauseTrek() { setState(() { isPaused = true; _stopwatch.stop(); }); }
  void _resumeTrek() { setState(() { isPaused = false; _stopwatch.start(); }); }
  
  void _finishTrek() { 
    setState(() { _isTracking = false; isPaused = false; _isAutoPaused = false; _stopwatch.stop(); _ticker?.cancel(); _stopTimer?.cancel(); AppSettings.amoledMode.value = false; }); 
    FlutterBackgroundService().invoke("stopService"); 
    _showSaveTrekDialog(); 
  }

  // --- UNIFIED PUBLISH METHOD ---
  Future<void> _publishUnifiedTrek(String name, String difficulty, bool isPrivate) async {
    if (_offlineTrekData.length < 2) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? 'guest_user';
    final linePoints = _offlineTrekData.map((p) => '${p.longitude} ${p.latitude}').join(', ');
    
    final payload = { 
      'creator_id': currentUserId, 
      'name': name, 
      'difficulty': difficulty, 
      'distance_meters': _calculateTotalDistance(), 
      'elevation_gain': _calculateTotalElevationGain(), 
      'route_geom': 'SRID=4326;LINESTRING($linePoints)', 
      'waypoints': _waypoints,
      'is_private': isPrivate // The new privacy flag!
    };
    
    try {
      await Supabase.instance.client.from('public_treks').insert(payload);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isPrivate ? 'Saved to private dashboard!' : 'Published "$name" to Explore!'), 
        backgroundColor: Colors.green
      ));
    } catch (_) {
      await OfflineSyncManager.savePending('public', payload);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Network. Saved locally.'), backgroundColor: Colors.orange));
    }
  }

  String _toDMS(double coordinate, bool isLat) {
    final dir = coordinate < 0 ? (isLat ? 'S' : 'W') : (isLat ? 'N' : 'E');
    final abs = coordinate.abs(); final deg = abs.floor(); final min = ((abs - deg) * 60).floor(); final sec = (((abs - deg) * 60) - min) * 60;
    return '$deg°$min\'${sec.toStringAsFixed(1)}"$dir';
  }

  void _showWaypointDialog() {
    if (_currentPosition == null) return;
    String selectedCategory = 'Viewpoint';
    showModalBottomSheet(
      context: context, backgroundColor: cardSurface, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset, left: 24, right: 24, top: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 24),
                  const Text('Drop Waypoint', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Mark your current GPS location', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12, runSpacing: 12,
                    children: [
                      _buildWaypointOption(Icons.camera_alt_outlined, 'Viewpoint', selectedCategory, () => setSheetState(() => selectedCategory = 'Viewpoint')),
                      _buildWaypointOption(Icons.water_drop_outlined, 'Water', selectedCategory, () => setSheetState(() => selectedCategory = 'Water')),
                      _buildWaypointOption(Icons.warning_amber_rounded, 'Hazard', selectedCategory, () => setSheetState(() => selectedCategory = 'Hazard')),
                      _buildWaypointOption(Icons.park_outlined, 'Camp', selectedCategory, () => setSheetState(() => selectedCategory = 'Camp')),
                      _buildWaypointOption(Icons.directions_walk, 'Trail Fork', selectedCategory, () => setSheetState(() => selectedCategory = 'Trail Fork')),
                      _buildWaypointOption(Icons.local_parking, 'Parking', selectedCategory, () => setSheetState(() => selectedCategory = 'Parking')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(style: const TextStyle(color: Colors.white, fontSize: 14), decoration: InputDecoration(hintText: 'Add an optional note...', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: bgColor, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), prefixIcon: const Icon(Icons.edit_note, color: Colors.grey))),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (_currentPosition != null) {
                          final lat = _currentPosition!.latitude; final lng = _currentPosition!.longitude;
                          _waypoints.add({'type': selectedCategory, 'lat': lat, 'lng': lng, 'timestamp': DateTime.now().toIso8601String()});
                          if (mapController != null) await mapController!.addCircle(CircleOptions(geometry: LatLng(lat, lng), circleColor: '#00BFFF', circleRadius: 8.0, circleStrokeWidth: 3.0, circleStrokeColor: '#1A1A1A'));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$selectedCategory added to map!'), backgroundColor: Colors.teal));
                        }
                      },
                      child: const Text('Save to Map', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWaypointOption(IconData icon, String label, String selectedCategory, VoidCallback onTap) {
    final isSelected = selectedCategory == label;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: (MediaQuery.of(context).size.width - 72) / 3,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: isSelected ? neonAccent.withValues(alpha: 0.15) : bgColor, border: Border.all(color: isSelected ? neonAccent : Colors.white10, width: 1.5), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [Icon(icon, color: isSelected ? neonAccent : Colors.white70, size: 28), const SizedBox(height: 8), Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  // --- UPDATED SAVE DIALOG ---
  void _showSaveTrekDialog() {
    final distKm = (_calculateTotalDistance() / 1000).toStringAsFixed(2);
    final elevGain = _calculateTotalElevationGain().toStringAsFixed(0);
    final nameController = TextEditingController(text: 'Trek on ${DateTime.now().day}/${DateTime.now().month}');
    String selectedDifficulty = 'Moderate';
    bool isPrivate = false; // Toggle state

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1E28), title: const Text('Finished Trek!', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Dist: $distKm km', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), Text('Gain: ${elevGain}m', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00C853)))]),
              const SizedBox(height: 16),
              TextField(controller: nameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Trek Name', labelStyle: TextStyle(color: Colors.grey), border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButton<String>(value: selectedDifficulty, isExpanded: true, dropdownColor: const Color(0xFF1B1E28), style: const TextStyle(color: Colors.white), items: const [DropdownMenuItem(value: 'Easy', child: Text('Easy')), DropdownMenuItem(value: 'Moderate', child: Text('Moderate')), DropdownMenuItem(value: 'Hard', child: Text('Hard'))], onChanged: (val) { if (val != null) setDState(() => selectedDifficulty = val); }),
              const SizedBox(height: 12),
              // New Public/Private Toggle Switch
              SwitchListTile(
                title: const Text('Make Private', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(isPrivate ? 'Only visible to you' : 'Visible on the Explore page', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                value: isPrivate,
                activeColor: const Color(0xFFD4FF00),
                onChanged: (val) => setDState(() => isPrivate = val),
                contentPadding: EdgeInsets.zero,
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () { Navigator.pop(ctx); _clearMapData(); }, child: const Text('Discard', style: TextStyle(color: Colors.redAccent))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4FF00), foregroundColor: Colors.black), 
              onPressed: () async { 
                Navigator.pop(ctx); 
                await _publishUnifiedTrek(nameController.text.trim(), selectedDifficulty, isPrivate); 
                _clearMapData(); 
              }, 
              child: const Text('Save Trek', style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
      ),
    );
  }
  
  String get _durationFormatted {
    final d = _stopwatch.elapsed;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  // --- LINKED METRIC CONVERSION FOR PACE ---
  String _calculatePace(bool isMetric) {
    if (_liveDistanceKm < 0.01) return '--:--';
    final totalMinutes = _stopwatch.elapsed.inSeconds / 60.0;
    final dist = isMetric ? _liveDistanceKm : (_liveDistanceKm * 0.621371);
    final paceDec = totalMinutes / dist;
    final pMins = paceDec.floor();
    final pSecs = ((paceDec - pMins) * 60).round();
    return '${pMins.toString().padLeft(2, '0')}:${pSecs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isFollowingRoute = widget.trekToFollow != null && _guidedTrekPoints.isNotEmpty;
    
    // --- LISTENS TO APP SETTINGS MAGIC ---
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.amoledMode,
      builder: (context, isAmoled, _) {
        final currentBg = isAmoled ? Colors.black : bgColor;
        final currentCardBg = isAmoled ? Colors.black : cardSurface;
        
        bool isMetric = AppSettings.metricUnits.value;
        String distUnit = isMetric ? 'km' : 'mi';
        String elevUnit = isMetric ? 'm' : 'ft';
        String speedUnit = isMetric ? 'km/h' : 'mph';

        double displayDist = isMetric ? _liveDistanceKm : (_liveDistanceKm * 0.621371);
        double displayElev = isMetric ? _liveElevationGain : (_liveElevationGain * 3.28084);
        double currentSpeedKmh = (_currentPosition?.speed ?? 0) * 3.6;
        double displaySpeed = isMetric ? currentSpeedKmh : (currentSpeedKmh * 0.621371);

        return Scaffold(
          backgroundColor: currentBg,
          body: SafeArea(
            child: Column(
              children: [
                // 1. TOP STATUS BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [const Icon(Icons.satellite_alt, color: neonAccent, size: 18), const SizedBox(width: 6), Text('GPS 3m', style: TextStyle(color: neonAccent.withValues(alpha: 0.8), fontWeight: FontWeight.bold, fontSize: 13))]),
                      Row(
                        children: [
                          Text('AMOLED', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)), 
                          const SizedBox(width: 8), 
                          SizedBox(
                            height: 24, 
                            child: Switch(
                              value: isAmoled, 
                              onChanged: (val) {
                                AppSettings.amoledMode.value = val;
                                if (!val && _currentPosition != null) { 
                                  _updateLiveRoute(); 
                                  _updatePucksOnMap(_currentPosition!); 
                                }
                              }, 
                              activeThumbColor: neonAccent, activeTrackColor: neonAccent.withValues(alpha: 0.3), inactiveTrackColor: Colors.white10
                            )
                          )
                        ]
                      )
                    ],
                  ),
                ),

                // 2. MASSIVE TELEMETRY (LINKED METRICS)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Column(
                    children: [
                      Text(_durationFormatted, style: TextStyle(color: isPaused ? Colors.grey : Colors.white, fontSize: 64, fontWeight: FontWeight.w900, letterSpacing: -2, height: 1.0)),
                      const SizedBox(height: 4),
                      const Text('ELAPSED TIME', style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildPrimaryMetric(displayDist.toStringAsFixed(2), distUnit, 'DISTANCE'),
                          Container(width: 1, height: 50, color: Colors.white10),
                          _buildPrimaryMetric(_calculatePace(isMetric), '/$distUnit', 'CURRENT PACE'),
                          Container(width: 1, height: 50, color: Colors.white10),
                          _buildPrimaryMetric(displayElev.toStringAsFixed(0), elevUnit, 'ELEV GAIN'),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. REAL LIVE MAP
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: currentCardBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          Offstage(
                            offstage: isAmoled,
                            child: MapLibreMap(
                              onMapCreated: (c) { 
                                mapController = c; 
                              },
                              onStyleLoadedCallback: () {
                                if (widget.trekToFollow != null) _loadGuidedTrek(widget.trekToFollow!); 
                                if (_currentPosition != null) _fetchInitialPosition(); 
                              },
                              styleString: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
                              initialCameraPosition: const CameraPosition(target: LatLng(12.3051, 76.6551), zoom: 16.0),
                              myLocationEnabled: false, compassEnabled: false,
                              onCameraTrackingDismissed: () => setState(() => _isCameraLocked = false),
                            ),
                          ),
                          if (isAmoled)
                            const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.battery_saver, color: neonAccent, size: 48), SizedBox(height: 12), Text('AMOLED SAVER ACTIVE', style: TextStyle(color: neonAccent, fontWeight: FontWeight.bold, letterSpacing: 2))])),
                          if (!_isCameraLocked && !isAmoled)
                            Positioned(
                              bottom: 16, right: 16,
                              child: FloatingActionButton(
                                mini: true, backgroundColor: cardSurface,
                                child: const Icon(Icons.my_location, color: Colors.white),
                                onPressed: () { setState(() => _isCameraLocked = true); if (_currentPosition != null && mapController != null) { mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), zoom: 17.5, bearing: _currentPosition!.heading >= 0 ? _currentPosition!.heading : 0.0, tilt: 45.0))); } },
                              )
                            )
                        ],
                      ),
                    ),
                  ),
                ),

                // 4. BOTTOM ACTION CONTROLS
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                  child: !_isTracking 
                    ? SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: neonAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), icon: const Icon(Icons.play_arrow, color: Colors.black, size: 28), label: Text(widget.trekToFollow != null ? 'START NAVIGATION' : 'START TREK', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)), onPressed: _startTrek))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          GestureDetector(
                            onTap: () => _showWaypointDialog(),
                            child: Container(width: 64, height: 64, decoration: BoxDecoration(color: currentCardBg, shape: BoxShape.circle, border: Border.all(color: Colors.white10)), child: const Icon(Icons.add_location_alt, color: Colors.white, size: 28)),
                          ),
                          GestureDetector(
                            onTap: () { setState(() => isPaused = !isPaused); if (isPaused) { _stopwatch.stop(); } else { _stopwatch.start(); } },
                            child: Container(
                              width: 88, height: 88,
                              decoration: BoxDecoration(color: isPaused ? currentCardBg : neonAccent, shape: BoxShape.circle, border: Border.all(color: isPaused ? neonAccent : Colors.transparent, width: 3), boxShadow: isPaused ? [] : [BoxShadow(color: neonAccent.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)]),
                              child: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: isPaused ? neonAccent : Colors.black, size: 48),
                            ),
                          ),
                          HoldToCompleteButton(onComplete: _finishTrek),
                        ],
                      ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildPrimaryMetric(String value, String unit, String label) {
    return Column(
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)), const SizedBox(width: 2), Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// -----------------------------------------------------------------------
// ANIMATED HOLD-TO-COMPLETE BUTTON
// -----------------------------------------------------------------------
class HoldToCompleteButton extends StatefulWidget {
  final VoidCallback onComplete;
  const HoldToCompleteButton({super.key, required this.onComplete});
  @override State<HoldToCompleteButton> createState() => _HoldToCompleteButtonState();
}

class _HoldToCompleteButtonState extends State<HoldToCompleteButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500)); _controller.addStatusListener((status) { if (status == AnimationStatus.completed) { widget.onComplete(); _controller.reset(); } }); }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  void _startHolding(TapDownDetails details) => _controller.forward();
  void _stopHolding() { if (_controller.status != AnimationStatus.completed) _controller.reverse(); }

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _startHolding, onTapUp: (_) => _stopHolding(), onTapCancel: _stopHolding,
      onTap: () { if (_controller.value == 0) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hold button to finish trek'))); },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(width: 76, height: 76, child: CircularProgressIndicator(value: _controller.value, strokeWidth: 4, color: Colors.redAccent, backgroundColor: Colors.transparent)),
              Transform.scale(scale: 1.0 - (_controller.value * 0.15), child: Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.15 + (_controller.value * 0.2)), shape: BoxShape.circle, border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5))), child: const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 32))),
            ],
          );
        },
      ),
    );
  }
}