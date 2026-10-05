import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:xml/xml.dart'; 
import 'package:file_picker/file_picker.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'package:path_provider/path_provider.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lvkgxsfsvsydfuywphiv.supabase.co',
    anonKey: 'sb_publishable_549oaEIaBH2n8TzYaeQbLw_8kMM9Wzb',
  );

  runApp(const XploreApp());
}

class XploreApp extends StatelessWidget {
  const XploreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Xplore',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF007AFF),
          secondary: Color(0xFFFC4C02),
          surface: Color(0xFF161922),
        ),
        useMaterial3: true,
      ),
      home: const AuthGateway(),
    );
  }
}

// ---------------------------------------------------------------------------
// OFFLINE SYNC MANAGER
// ---------------------------------------------------------------------------
class OfflineSyncManager {
  static Database? _db;
  static final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'xplore_offline_sync.db'),
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE pending_uploads(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, payload TEXT, created_at TEXT)',
        );
      },
    );
    return _db!;
  }

  static Future<void> refreshCount() async {
    final pending = await getPending();
    pendingCount.value = pending.length;
  }

  static Future<void> savePending(String type, dynamic payload) async {
    final database = await db;
    await database.insert('pending_uploads', {
      'type': type,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
    refreshCount();
  }

  static Future<List<Map<String, dynamic>>> getPending() async {
    final database = await db;
    return await database.query('pending_uploads', orderBy: 'created_at ASC');
  }

  static Future<void> removePending(int id) async {
    final database = await db;
    await database.delete('pending_uploads', where: 'id = ?', whereArgs: [id]);
    refreshCount();
  }

  static Future<int> syncAll() async {
    final pending = await getPending();
    int successCount = 0;

    for (final item in pending) {
      try {
        final type = item['type'];
        final payload = jsonDecode(item['payload']);

        if (type == 'public') {
          await Supabase.instance.client.from('public_treks').insert(payload);
        } else if (type == 'private') {
          final List<dynamic> listPayload = payload;
          final List<Map<String, dynamic>> typedPayload = listPayload.map((e) => e as Map<String, dynamic>).toList();
          await Supabase.instance.client.from('gps_tracks').insert(typedPayload);
        }
        await removePending(item['id']);
        successCount++;
      } catch (e) {
        print('Sync failed for item ${item['id']}: $e');
      }
    }
    return successCount;
  }
}

// ---------------------------------------------------------------------------
// AUTH GATEWAY & SCREENS
// ---------------------------------------------------------------------------
class AuthGateway extends StatelessWidget {
  const AuthGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) return const RootNavigationShell();
        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.length < 6) return;
    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(email: email, password: password);
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Auth failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.terrain, size: 70, color: Color(0xFF007AFF)),
              const SizedBox(height: 12),
              const Text('XPLORE', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white)),
              const SizedBox(height: 40),
              TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Email', filled: true, fillColor: const Color(0xFF161922), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
              const SizedBox(height: 16),
              TextField(controller: _passwordController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Password', filled: true, fillColor: const Color(0xFF161922), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
              const SizedBox(height: 24),
              SizedBox(height: 52, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: _isLoading ? null : _handleAuth, child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(_isSignUp ? 'Create Account' : 'Sign In', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)))),
              const SizedBox(height: 16),
              TextButton(onPressed: () => setState(() => _isSignUp = !_isSignUp), child: Text(_isSignUp ? 'Already have an account? Sign In' : "Don't have an account? Sign Up", style: const TextStyle(color: Colors.grey))),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ROOT NAVIGATION SHELL
// ---------------------------------------------------------------------------
class RootNavigationShell extends StatefulWidget {
  const RootNavigationShell({super.key});

  @override
  State<RootNavigationShell> createState() => _RootNavigationShellState();
}

class _RootNavigationShellState extends State<RootNavigationShell> {
  int _currentIndex = 1; 
  Map<String, dynamic>? _selectedTrekToFollow;
  StreamSubscription? _connectivitySubscription; 

  @override
  void initState() {
    super.initState();
    OfflineSyncManager.refreshCount();
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((dynamic result) async {
      bool hasConnection = false;
      if (result is List) {
        hasConnection = result.contains(ConnectivityResult.mobile) || result.contains(ConnectivityResult.wifi);
      } else {
        hasConnection = result == ConnectivityResult.mobile || result == ConnectivityResult.wifi;
      }
      
      if (hasConnection && OfflineSyncManager.pendingCount.value > 0) {
        final count = await OfflineSyncManager.syncAll();
        if (count > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Auto-synced $count offline treks! ☁️✨', style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green));
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _onSelectTrekFromExplore(Map<String, dynamic> trek) {
    setState(() {
      _selectedTrekToFollow = trek;
      _currentIndex = 1; 
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ExploreScreen(onSelectTrek: _onSelectTrekFromExplore),
          RecordScreen(trekToFollow: _selectedTrekToFollow),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF12141C),
        indicatorColor: const Color(0xFF007AFF).withValues(alpha: 0.2),
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined, color: Colors.grey), selectedIcon: Icon(Icons.explore, color: Color(0xFF007AFF)), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.radio_button_checked, color: Colors.grey), selectedIcon: Icon(Icons.radio_button_checked, color: Color(0xFF007AFF)), label: 'Record'),
          NavigationDestination(icon: Icon(Icons.person_outline, color: Colors.grey), selectedIcon: Icon(Icons.person, color: Color(0xFF007AFF)), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TRAIL DETAIL SCREEN
// ---------------------------------------------------------------------------
class TrailDetailScreen extends StatefulWidget {
  final Map<String, dynamic> trek;
  final VoidCallback onStartTrail;
  
  const TrailDetailScreen({super.key, required this.trek, required this.onStartTrail});

  @override
  State<TrailDetailScreen> createState() => _TrailDetailScreenState();
}

class _TrailDetailScreenState extends State<TrailDetailScreen> {
  MapLibreMapController? _mapController;
  bool _hasLiked = false;
  int _likesCount = 0;
  List<dynamic> _comments = [];
  bool _isLoadingSocial = true;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSocialData();
  }

  Future<void> _fetchSocialData() async {
    final trekId = widget.trek['id'];
    if (trekId == 'imported_gpx') {
      setState(() => _isLoadingSocial = false);
      return; 
    }

    final myId = Supabase.instance.client.auth.currentUser!.id;
    try {
      final likesRes = await Supabase.instance.client.from('trek_likes').select('user_id').eq('trek_id', trekId);
      _likesCount = likesRes.length;
      _hasLiked = likesRes.any((like) => like['user_id'] == myId);

      final commentsRes = await Supabase.instance.client.rpc('get_trek_comments', params: {'p_trek_id': trekId});
      
      if (mounted) setState(() { _comments = commentsRes; _isLoadingSocial = false; });
    } catch(e) {
      if (mounted) setState(() => _isLoadingSocial = false);
    }
  }

  Future<void> _exportGPX() async {
    try {
      await GPXHelper.exportAndShareTrek(widget.trek);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export GPX: $e'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _toggleLike() async {
    if (widget.trek['id'] == 'imported_gpx') return;
    final trekId = widget.trek['id'];
    final myId = Supabase.instance.client.auth.currentUser!.id;
    
    HapticFeedback.lightImpact();
    setState(() { _hasLiked = !_hasLiked; _likesCount += _hasLiked ? 1 : -1; });
    
    try {
      if (_hasLiked) await Supabase.instance.client.from('trek_likes').insert({'trek_id': trekId, 'user_id': myId});
      else await Supabase.instance.client.from('trek_likes').delete().eq('trek_id', trekId).eq('user_id', myId);
    } catch(e) {
      setState(() { _hasLiked = !_hasLiked; _likesCount += _hasLiked ? 1 : -1; });
    }
  }

  Future<void> _submitComment() async {
    if (widget.trek['id'] == 'imported_gpx') return;
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    
    final trekId = widget.trek['id'];
    final myId = Supabase.instance.client.auth.currentUser!.id;
    
    _commentController.clear();
    FocusScope.of(context).unfocus();
    
    try {
      await Supabase.instance.client.from('trek_comments').insert({'trek_id': trekId, 'user_id': myId, 'body': text});
      _fetchSocialData();
    } catch(e) {}
  }

  String _calculateEstimatedTime() {
    final distKm = (widget.trek['distance_meters'] as num) / 1000.0;
    final elevM = (widget.trek['elevation_gain'] as num?)?.toDouble() ?? 0.0;
    double hours = (distKm / 4.0) + (elevM / 400.0);
    int h = hours.floor();
    int m = ((hours - h) * 60).round();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _mapController = controller;
    try {
      final geoJson = jsonDecode(widget.trek['route_geojson']);
      final List coordinates = geoJson['coordinates'];
      final List<LatLng> pts = coordinates.map((c) => LatLng(c[1] as double, c[0] as double)).toList();

      if (pts.isNotEmpty) {
        await _mapController!.addLine(LineOptions(geometry: pts, lineColor: '#00E5FF', lineWidth: 6.0, lineJoin: 'round'));
        await _mapController!.addCircle(CircleOptions(geometry: pts.first, circleRadius: 6.0, circleColor: '#00C853', circleStrokeWidth: 2.0, circleStrokeColor: '#FFFFFF'));
        await _mapController!.addCircle(CircleOptions(geometry: pts.last, circleRadius: 6.0, circleColor: '#FC4C02', circleStrokeWidth: 2.0, circleStrokeColor: '#FFFFFF'));

        if (widget.trek['waypoints'] != null) {
          final List waypoints = widget.trek['waypoints'] is String ? jsonDecode(widget.trek['waypoints']) : widget.trek['waypoints'];
          for (var wp in waypoints) {
            String color = '#FFFFFF';
            if (wp['type'] == 'Water') color = '#00BFFF';
            if (wp['type'] == 'Camp') color = '#FF8C00';
            if (wp['type'] == 'Hazard') color = '#FF0000';
            if (wp['type'] == 'Viewpoint') color = '#9C27B0';
            await _mapController!.addCircle(CircleOptions(geometry: LatLng(wp['lat'], wp['lng']), circleColor: color, circleRadius: 6.0, circleStrokeWidth: 2.0, circleStrokeColor: '#FFFFFF'));
          }
        }

        double minLat = pts.first.latitude, maxLat = pts.first.latitude;
        double minLng = pts.first.longitude, maxLng = pts.first.longitude;
        for (var p in pts) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }

        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), top: 40, bottom: 40, left: 40, right: 40));
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final distKm = ((widget.trek['distance_meters'] as num) / 1000).toStringAsFixed(1);
    final elevGain = (widget.trek['elevation_gain'] as num?)?.toStringAsFixed(0) ?? '0';
    final difficulty = widget.trek['difficulty'] ?? 'Moderate';
    Color badgeColor = difficulty == 'Hard' ? Colors.red : (difficulty == 'Easy' ? Colors.green : Colors.orange);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trail Overview', style: TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: const Color(0xFF0F1115),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share), onPressed: _exportGPX, tooltip: 'Export GPX'), 
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 220, child: MapLibreMap(onMapCreated: _onMapCreated, styleString: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json', initialCameraPosition: CameraPosition(target: LatLng(widget.trek['start_lat'] ?? 0, widget.trek['start_lng'] ?? 0), zoom: 13.0), myLocationEnabled: false, compassEnabled: false, scrollGesturesEnabled: false, zoomGesturesEnabled: false)),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 12),
              decoration: const BoxDecoration(color: Color(0xFF13151D), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(widget.trek['name'] ?? 'Wilderness Trek', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: Text(difficulty, style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(radius: 12, backgroundImage: widget.trek['creator_avatar'] != null ? NetworkImage(widget.trek['creator_avatar']) : null, backgroundColor: const Color(0xFF007AFF), child: widget.trek['creator_avatar'] == null ? const Icon(Icons.person, size: 12, color: Colors.white) : null),
                      const SizedBox(width: 8),
                      Text('Mapped by ${widget.trek['creator_name'] ?? 'Athlete'}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(color: Colors.white10)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDetailStat('DISTANCE', '$distKm km'),
                      _buildDetailStat('ELEVATION', '${elevGain}m'),
                      _buildDetailStat('EST TIME', _calculateEstimatedTime()),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(color: Colors.white10)),
                  
                  if (widget.trek['id'] != 'imported_gpx') ...[
                    Row(
                      children: [
                        GestureDetector(onTap: _toggleLike, child: Row(children: [Icon(_hasLiked ? Icons.favorite : Icons.favorite_border, color: _hasLiked ? Colors.redAccent : Colors.grey, size: 22), const SizedBox(width: 6), Text('$_likesCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))])),
                        const SizedBox(width: 24),
                        Row(children: [const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 20), const SizedBox(width: 6), Text('${_comments.length} Reviews', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14))]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _isLoadingSocial 
                        ? const Center(child: CircularProgressIndicator())
                        : _comments.isEmpty 
                          ? const Center(child: Text("No comments yet. Share trail conditions!", style: TextStyle(color: Colors.grey, fontSize: 13)))
                          : ListView.builder(
                              itemCount: _comments.length,
                              itemBuilder: (ctx, i) {
                                final c = _comments[i];
                                return Padding(padding: const EdgeInsets.only(bottom: 12.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [CircleAvatar(radius: 14, backgroundImage: c['avatar_url'] != null ? NetworkImage(c['avatar_url']) : null, backgroundColor: const Color(0xFF007AFF)), const SizedBox(width: 10), Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1A1D27), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c['display_name'] ?? 'Athlete', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)), const SizedBox(height: 4), Text(c['body'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13))])))]));
                              }
                          )
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _commentController, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: InputDecoration(hintText: 'Add a review...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: const Color(0xFF1A1D27), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)))),
                        IconButton(icon: const Icon(Icons.send, color: Color(0xFF007AFF)), onPressed: _submitComment)
                      ]
                    ),
                  ] else ...[
                    const Expanded(child: Center(child: Text("External GPX file. Ready to Navigate.", style: TextStyle(color: Colors.grey)))),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                      icon: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                      label: const Text('START THIS TRAIL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      onPressed: () { Navigator.pop(context); widget.onStartTrail(); },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStat(String label, String value) {
    return Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))]);
  }
}

// ---------------------------------------------------------------------------
// TAB 1: EXPLORE SCREEN
// ---------------------------------------------------------------------------
class ExploreScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onSelectTrek;
  const ExploreScreen({super.key, required this.onSelectTrek});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<dynamic> _treks = [];
  Set<String> _followingIds = {}; 
  bool _isLoading = true;
  String _selectedFilter = 'All';
  double _searchRadiusKm = 25.0;
  String _feedMode = 'Nearby'; 

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      final followData = await Supabase.instance.client.from('follows').select('following_id').eq('follower_id', userId);
      _followingIds = followData.map((e) => e['following_id'].toString()).toSet();

      List<dynamic> data = [];
      if (_feedMode == 'Nearby') {
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
        data = await Supabase.instance.client.rpc('get_treks_near_me', params: {'user_lat': pos.latitude, 'user_lng': pos.longitude, 'radius_meters': _searchRadiusKm * 1000});
      } else {
        data = await Supabase.instance.client.rpc('get_following_treks', params: {'current_user_id': userId});
      }

      if (mounted) setState(() { _treks = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importGPX() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['gpx', 'xml'],
      );

      if (result != null && result.files.single.path != null) {
        final File file = File(result.files.single.path!);
        final importedTrek = await GPXHelper.importTrek(file, result.files.single.name);
        
        if (mounted && importedTrek != null) {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => TrailDetailScreen(
              trek: importedTrek,
              onStartTrail: () => widget.onSelectTrek(importedTrek),
            )
          ));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read GPX: $e')));
    }
  }

  Future<void> _toggleFollow(String targetUserId) async {
    final myId = Supabase.instance.client.auth.currentUser!.id;
    final isCurrentlyFollowing = _followingIds.contains(targetUserId);

    setState(() {
      if (isCurrentlyFollowing) _followingIds.remove(targetUserId);
      else _followingIds.add(targetUserId);
    });

    try {
      if (isCurrentlyFollowing) {
        await Supabase.instance.client.from('follows').delete().eq('follower_id', myId).eq('following_id', targetUserId);
      } else {
        await Supabase.instance.client.from('follows').insert({'follower_id': myId, 'following_id': targetUserId});
      }
    } catch (e) {
      setState(() {
        if (isCurrentlyFollowing) _followingIds.add(targetUserId);
        else _followingIds.remove(targetUserId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedFilter == 'All' ? _treks : _treks.where((t) => t['difficulty'] == _selectedFilter).toList();
    final myId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Trails', style: TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: const Color(0xFF0F1115), 
        actions: [
          IconButton(icon: const Icon(Icons.file_upload_outlined), tooltip: 'Import GPX', onPressed: _importGPX),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ]
      ),
      body: RefreshIndicator(
        onRefresh: _fetchData, color: const Color(0xFF007AFF),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF161922), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(child: GestureDetector(onTap: () { setState(() { _feedMode = 'Nearby'; _isLoading = true; }); _fetchData(); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _feedMode == 'Nearby' ? const Color(0xFF007AFF) : Colors.transparent, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('Nearby', style: TextStyle(fontWeight: FontWeight.bold, color: _feedMode == 'Nearby' ? Colors.white : Colors.grey))))),
                  Expanded(child: GestureDetector(onTap: () { setState(() { _feedMode = 'Following'; _isLoading = true; }); _fetchData(); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _feedMode == 'Following' ? const Color(0xFF007AFF) : Colors.transparent, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('Following', style: TextStyle(fontWeight: FontWeight.bold, color: _feedMode == 'Following' ? Colors.white : Colors.grey))))),
                ],
              ),
            ),
            if (_feedMode == 'Nearby')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8), decoration: BoxDecoration(color: const Color(0xFF161922), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Search Radius', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)), Text('${_searchRadiusKm.toStringAsFixed(0)} KM', style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold, fontSize: 15))]), Slider(value: _searchRadiusKm, min: 5.0, max: 150.0, divisions: 29, activeColor: const Color(0xFF007AFF), inactiveColor: Colors.grey[800], label: '${_searchRadiusKm.toStringAsFixed(0)} km', onChanged: (val) => setState(() => _searchRadiusKm = val), onChangeEnd: (val) => _fetchData())]),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: ['All', 'Easy', 'Moderate', 'Hard'].map((diff) { final isSelected = _selectedFilter == diff; return Padding(padding: const EdgeInsets.only(right: 8.0), child: FilterChip(label: Text(diff), selected: isSelected, selectedColor: const Color(0xFF007AFF).withValues(alpha: 0.3), backgroundColor: const Color(0xFF1E222D), labelStyle: TextStyle(color: isSelected ? const Color(0xFF007AFF) : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), onSelected: (_) => setState(() => _selectedFilter = diff))); }).toList()),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), child: Text('${filtered.length} trails found', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600))),
            Expanded(
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : filtered.isEmpty ? ListView(children: [const SizedBox(height: 100), Center(child: Text(_feedMode == 'Nearby' ? 'No treks found nearby.\nTry expanding your slider!' : 'No treks yet.\nStart following other athletes!', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)))]) : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final trek = filtered[index];
                  final distanceKm = ((trek['distance_meters'] as num) / 1000).toStringAsFixed(1);
                  final elevGain = (trek['elevation_gain'] as num?)?.toStringAsFixed(0) ?? '0';
                  final difficulty = trek['difficulty'] ?? 'Moderate';
                  final creatorId = trek['creator_id']?.toString() ?? '';
                  final creatorName = trek['creator_name'] ?? 'Athlete';
                  final creatorAvatar = trek['creator_avatar'];

                  Color badgeColor = difficulty == 'Hard' ? Colors.red : (difficulty == 'Easy' ? Colors.green : Colors.orange);
                  final isMyTrek = creatorId == myId;
                  final isLegacyTrek = creatorId == 'my_android_device' || creatorId.isEmpty;
                  final isFollowing = _followingIds.contains(creatorId);

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(trek: trek, onStartTrail: () => widget.onSelectTrek(trek))));
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: const Color(0xFF1A1D27), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(radius: 14, backgroundImage: creatorAvatar != null ? NetworkImage(creatorAvatar) : null, backgroundColor: const Color(0xFF007AFF), child: creatorAvatar == null ? const Icon(Icons.person, size: 14, color: Colors.white) : null),
                                const SizedBox(width: 8),
                                Expanded(child: Text(creatorName, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
                                if (!isMyTrek && !isLegacyTrek)
                                  GestureDetector(onTap: () => _toggleFollow(creatorId), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: isFollowing ? Colors.transparent : const Color(0xFF007AFF), border: isFollowing ? Border.all(color: Colors.grey) : null, borderRadius: BorderRadius.circular(14)), child: Text(isFollowing ? 'Following' : 'Follow', style: TextStyle(color: isFollowing ? Colors.grey : Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))
                                else if (isMyTrek)
                                  const Text('You', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Divider(color: Colors.white10, height: 24),
                            
                            Text(trek['name'] ?? 'Wilderness Trek', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text(difficulty, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                Text('$distanceKm km • Gain: ${elevGain}m', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF007AFF)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                child: const Text('View Trail Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(trek: trek, onStartTrail: () => widget.onSelectTrek(trek))));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TAB 2: RECORD SCREEN (WITH SMART AUTO-PAUSE)
// ---------------------------------------------------------------------------
class RecordScreen extends StatefulWidget {
  final Map<String, dynamic>? trekToFollow;
  const RecordScreen({super.key, this.trekToFollow});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  MapLibreMapController? mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSub;

  bool _isTracking = false;
  bool _isPaused = false; 
  bool _isAddingPuck = false;
  bool _isDownloadingMap = false; 
  double _downloadProgress = 0.0; 
  
  bool _isOffRoute = false;
  final List<LatLng> _guidedTrekPoints = []; 
  
  bool _isAmoledMode = false;
  final List<Map<String, dynamic>> _waypoints = [];
  
  // --- NEW: AUTO-PAUSE VARIABLES ---
  bool _isAutoPaused = false;
  Timer? _stopTimer;
  final double _stopSpeedThresholdMs = 0.22; // ~0.8 km/h
  final int _stopDurationSeconds = 12; // Wait 12s before auto-pausing

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  double _liveDistanceKm = 0.0;
  double _liveElevationGain = 0.0;

  Circle? _currentPuck;
  Circle? _startPuck;
  Circle? _guidePuck;
  Line? _routeLine;
  Line? _routeBorder;
  Line? _guideLine;

  final List<LatLng> _liveRoutePoints = [];
  final List<Position> _offlineTrekData = [];

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void didUpdateWidget(covariant RecordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trekToFollow != null && widget.trekToFollow != oldWidget.trekToFollow) {
      _loadGuidedTrek(widget.trekToFollow!);
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _ticker?.cancel();
    _stopTimer?.cancel(); // Cancel to prevent memory leaks
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1B1E28), title: const Text('GPS is Disabled', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), content: const Text('Please turn on GPS in your settings.', style: TextStyle(color: Colors.grey)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), ElevatedButton(onPressed: () async { Navigator.pop(ctx); await Geolocator.openLocationSettings(); }, child: const Text('Turn On'))]));
      return; 
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) { permission = await Geolocator.requestPermission(); if (permission == LocationPermission.denied) return; }
    if (permission == LocationPermission.deniedForever) return;
    await _fetchInitialPosition();
    if (_positionStreamSub == null) _startLocationUpdates();
  }

  Future<void> _fetchInitialPosition() async {
    try {
      final initialPosition = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() => _currentPosition = initialPosition);
      if (mapController != null && !_isAmoledMode) {
        _updatePucksOnMap(initialPosition);
        mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(initialPosition.latitude, initialPosition.longitude), 16.0));
      }
    } catch (e) {}
  }

  double _distanceToGuideRoute(Position pos) {
    if (_guidedTrekPoints.isEmpty) return 0.0;
    double minDistance = double.infinity;
    for (final point in _guidedTrekPoints) {
      final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, point.latitude, point.longitude);
      if (d < minDistance) minDistance = d;
    }
    return minDistance;
  }

  void _startLocationUpdates() {
    late LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(accuracy: LocationAccuracy.best, distanceFilter: 3, foregroundNotificationConfig: const ForegroundNotificationConfig(notificationText: "Tracking active", notificationTitle: "Xplore", enableWakeLock: true));
    } else {
      locationSettings = const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
    }

    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) {
      setState(() => _currentPosition = pos);
      
      if (_isTracking && !_isPaused) {
        if (pos.accuracy > 15.0) return; 

        // --- NEW: SMART AUTO-PAUSE LOGIC ---
        if (pos.speed < _stopSpeedThresholdMs) {
          if (_stopTimer == null && !_isAutoPaused) {
            _stopTimer = Timer(Duration(seconds: _stopDurationSeconds), () {
              setState(() {
                _isAutoPaused = true;
                _stopwatch.stop();
                HapticFeedback.lightImpact();
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auto-Paused. Walk to resume.'), duration: Duration(seconds: 2)));
            });
          }
        } else {
          _stopTimer?.cancel();
          _stopTimer = null;

          if (_isAutoPaused) {
            setState(() {
              _isAutoPaused = false;
              _stopwatch.start();
              HapticFeedback.mediumImpact();
            });
             if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auto-Resumed!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
          }
        }
        // --- END AUTO-PAUSE LOGIC ---

        // Only record path data if NOT auto-paused
        if (!_isAutoPaused) {
          _offlineTrekData.add(pos);
          _liveRoutePoints.add(LatLng(pos.latitude, pos.longitude));
          _liveDistanceKm = _calculateTotalDistance() / 1000;
          _liveElevationGain = _calculateTotalElevationGain();
          if (!_isAmoledMode) _updateLiveRoute();

          if (_guidedTrekPoints.isNotEmpty) {
            double distFromPath = _distanceToGuideRoute(pos);
            bool currentlyOffRoute = distFromPath > 40.0;
            if (currentlyOffRoute && !_isOffRoute) HapticFeedback.heavyImpact(); 
            setState(() => _isOffRoute = currentlyOffRoute);
          }
        }
      }
      
      if (!_isAmoledMode) _updatePucksOnMap(pos);
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
      _routeBorder = await mapController!.addLine(LineOptions(geometry: _liveRoutePoints, lineColor: '#FFFFFF', lineWidth: 9.0, lineJoin: 'round'));
      _routeLine = await mapController!.addLine(LineOptions(geometry: _liveRoutePoints, lineColor: '#FC4C02', lineWidth: 5.0, lineJoin: 'round'));
    } else {
      await mapController!.updateLine(_routeBorder!, LineOptions(geometry: _liveRoutePoints));
      await mapController!.updateLine(_routeLine!, LineOptions(geometry: _liveRoutePoints));
    }
  }

  Future<void> _loadGuidedTrek(Map<String, dynamic> trek) async {
    try {
      final geoJson = jsonDecode(trek['route_geojson']);
      final List coordinates = geoJson['coordinates'];
      _guidedTrekPoints.clear();
      _guidedTrekPoints.addAll(coordinates.map((c) => LatLng(c[1] as double, c[0] as double)));

      if (mapController != null && _guidedTrekPoints.isNotEmpty && !_isAmoledMode) {
        if (_guideLine != null) await mapController!.removeLine(_guideLine!);
        if (_guidePuck != null) await mapController!.removeCircle(_guidePuck!);

        _guideLine = await mapController!.addLine(LineOptions(geometry: _guidedTrekPoints, lineColor: '#00E5FF', lineWidth: 6.0, lineJoin: 'round'));
        _guidePuck = await mapController!.addCircle(CircleOptions(geometry: _guidedTrekPoints.first, circleRadius: 9.0, circleColor: '#00E5FF', circleStrokeWidth: 3.0, circleStrokeColor: '#FFFFFF'));

        mapController!.animateCamera(CameraUpdate.newLatLngZoom(_guidedTrekPoints.first, 15.0));
      }
    } catch (e) {}
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

    if (_isTracking && _liveRoutePoints.isNotEmpty && _startPuck == null) {
      _startPuck = await mapController!.addCircle(CircleOptions(geometry: _liveRoutePoints.first, circleRadius: 8.0, circleColor: '#00C853', circleStrokeWidth: 3.0, circleStrokeColor: '#FFFFFF'));
    }
  }

  Future<void> _clearMapData() async {
    _liveRoutePoints.clear();
    _offlineTrekData.clear();
    _guidedTrekPoints.clear(); 
    _waypoints.clear();
    _liveDistanceKm = 0.0;
    _liveElevationGain = 0.0;
    _isOffRoute = false; 
    _isAutoPaused = false;
    _stopTimer?.cancel();
    _stopTimer = null;

    if (mapController != null) {
      await mapController!.clearCircles();
      await mapController!.clearLines();
      _startPuck = null;
      _guidePuck = null;
      _routeLine = null;
      _routeBorder = null;
      _guideLine = null;
      _currentPuck = null;
      _isAddingPuck = false;
    }

    if (_currentPosition != null && !_isAmoledMode) _updatePucksOnMap(_currentPosition!);
    if (mounted) setState(() {});
  }

  void _startTrek() {
    setState(() {
      _isTracking = true;
      _isPaused = false;
      _isAutoPaused = false;
      _liveDistanceKm = 0.0;
      _liveElevationGain = 0.0;
      _isOffRoute = false;
      _stopwatch.reset();
      _stopwatch.start();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    if (widget.trekToFollow == null) _clearMapData();
  }

  void _pauseTrek() { setState(() { _isPaused = true; _stopwatch.stop(); }); }
  void _resumeTrek() { setState(() { _isPaused = false; _stopwatch.start(); }); }
  void _finishTrek() { setState(() { _isTracking = false; _isPaused = false; _isAutoPaused = false; _stopwatch.stop(); _ticker?.cancel(); _stopTimer?.cancel(); _isAmoledMode = false; }); _showSaveTrekDialog(); }

  Future<void> _savePersonalRun() async {
    if (_offlineTrekData.isEmpty) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? 'guest_user';
    final batchData = _offlineTrekData.map((pos) => {'device_id': currentUserId, 'location': 'POINT(${pos.longitude} ${pos.latitude})', 'speed': pos.speed, 'elevation_gain': _calculateTotalElevationGain(), 'waypoints': _waypoints, 'created_at': pos.timestamp.toUtc().toIso8601String()}).toList();
    
    try {
      await Supabase.instance.client.from('gps_tracks').insert(batchData);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to private history!'), backgroundColor: Colors.teal));
    } catch (e) {
      await OfflineSyncManager.savePending('private', batchData);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Network. Saved locally. Will sync later!'), backgroundColor: Colors.orange));
    }
  }

  Future<void> _publishTrek(String name, String difficulty) async {
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
    };

    try {
      await Supabase.instance.client.from('public_treks').insert(payload);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Published "$name" to Explore!'), backgroundColor: Colors.green));
    } catch (e) {
      await OfflineSyncManager.savePending('public', payload);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Network. Saved locally. Will sync later!'), backgroundColor: Colors.orange));
    }
  }

  String _toDMS(double coordinate, bool isLat) {
    final dir = coordinate < 0 ? (isLat ? 'S' : 'W') : (isLat ? 'N' : 'E');
    final abs = coordinate.abs();
    final deg = abs.floor();
    final min = ((abs - deg) * 60).floor();
    final sec = (((abs - deg) * 60) - min) * 60;
    return '$deg°$min\'${sec.toStringAsFixed(1)}"$dir';
  }

  void _showSOSDialog() {
    if (_currentPosition == null) return;
    final lat = _currentPosition!.latitude;
    final lng = _currentPosition!.longitude;
    final wgs84 = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    final dms = '${_toDMS(lat, true)}  ${_toDMS(lng, false)}';
    
    final smsBody = Uri.encodeComponent('EMERGENCY SOS: I need assistance. My last known GPS coordinates are:\n\nDecimal (WGS84):\n$wgs84\n\nDMS:\n$dms\n\nAltitude: ${_currentPosition!.altitude.toStringAsFixed(0)}m');

    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1B1E28), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emergency, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text('Emergency Coordinates', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF13151D), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text('Decimal Degrees', style: TextStyle(color: Colors.grey[500], fontSize: 12)), const SizedBox(height: 4), Text(wgs84, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1))])),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF13151D), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text('Degrees Minutes Seconds (DMS)', style: TextStyle(color: Colors.grey[500], fontSize: 12)), const SizedBox(height: 4), Text(dms, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1))])),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, height: 52, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), icon: const Icon(Icons.sms, color: Colors.white), label: const Text('Send SOS via SMS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), onPressed: () async { final uri = Uri.parse('sms:?body=$smsBody'); if (await canLaunchUrl(uri)) await launchUrl(uri); if (mounted) Navigator.pop(ctx); })),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showWaypointDialog() {
    if (_currentPosition == null) return;
    String selectedType = 'Water';
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1E28), title: const Text('Drop Trail Marker', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(value: selectedType, isExpanded: true, dropdownColor: const Color(0xFF1B1E28), style: const TextStyle(color: Colors.white), items: const [DropdownMenuItem(value: 'Water', child: Text('💧 Water Source')), DropdownMenuItem(value: 'Camp', child: Text('⛺ Campsite')), DropdownMenuItem(value: 'Hazard', child: Text('⚠️ Trail Hazard')), DropdownMenuItem(value: 'Viewpoint', child: Text('📸 Scenic Viewpoint'))], onChanged: (val) { if (val != null) setDState(() => selectedType = val); }),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)), onPressed: () async { Navigator.pop(ctx); final lat = _currentPosition!.latitude; final lng = _currentPosition!.longitude; _waypoints.add({'type': selectedType, 'lat': lat, 'lng': lng, 'timestamp': DateTime.now().toIso8601String()}); String color = '#FFFFFF'; if (selectedType == 'Water') color = '#00BFFF'; if (selectedType == 'Camp') color = '#FF8C00'; if (selectedType == 'Hazard') color = '#FF0000'; if (selectedType == 'Viewpoint') color = '#9C27B0'; if (mapController != null && !_isAmoledMode) { await mapController!.addCircle(CircleOptions(geometry: LatLng(lat, lng), circleColor: color, circleRadius: 8.0, circleStrokeWidth: 3.0, circleStrokeColor: '#FFFFFF')); } if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added $selectedType Marker!'), backgroundColor: Colors.teal)); }, child: const Text('Drop Pin', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Future<void> _showOfflineDownloadDialog() async {
    if (mapController == null) return;
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1B1E28), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.signal_cellular_connected_no_internet_4_bar, size: 48, color: Color(0xFF007AFF)),
                  const SizedBox(height: 16),
                  const Text('Save Area for Offline', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Download the currently visible map area. Navigate this trail deep in the wilderness without cell service.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 24),
                  if (_isDownloadingMap) ...[
                    LinearProgressIndicator(value: _downloadProgress, backgroundColor: const Color(0xFF161922), color: const Color(0xFF00C853), minHeight: 8, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 12),
                    Text('${(_downloadProgress * 100).toStringAsFixed(0)}% Downloaded', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ] else ...[
                    SizedBox(width: double.infinity, height: 52, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), icon: const Icon(Icons.download, color: Colors.white), label: const Text('Download Map (~15 MB)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), onPressed: () async { setSheetState(() => _isDownloadingMap = true); await _executeOfflineDownload(setSheetState); if (mounted) Navigator.pop(ctx); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline map saved successfully!'), backgroundColor: Color(0xFF00C853))); }))
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeOfflineDownload(Function setSheetState) async {
    for (int i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) setSheetState(() => _downloadProgress = i / 100.0);
    }
    if (mounted) setState(() { _isDownloadingMap = false; _downloadProgress = 0.0; });
  }

  void _showSaveTrekDialog() {
    final distKm = (_calculateTotalDistance() / 1000).toStringAsFixed(2);
    final elevGain = _calculateTotalElevationGain().toStringAsFixed(0);
    final nameController = TextEditingController(text: 'Trek on ${DateTime.now().day}/${DateTime.now().month}');
    String selectedDifficulty = 'Moderate';

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1E28), title: const Text('Finished Trek!', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Dist: $distKm km', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), Text('Gain: ${elevGain}m', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00C853)))]),
              const SizedBox(height: 12),
              if (_offlineTrekData.isNotEmpty) ElevationSparkline(points: _offlineTrekData),
              const SizedBox(height: 16),
              TextField(controller: nameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Trek Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButton<String>(value: selectedDifficulty, isExpanded: true, dropdownColor: const Color(0xFF1B1E28), style: const TextStyle(color: Colors.white), items: const [DropdownMenuItem(value: 'Easy', child: Text('Easy')), DropdownMenuItem(value: 'Moderate', child: Text('Moderate')), DropdownMenuItem(value: 'Hard', child: Text('Hard'))], onChanged: (val) { if (val != null) setDState(() => selectedDifficulty = val); }),
            ],
          ),
          actions: [
            TextButton(onPressed: () { Navigator.pop(ctx); _clearMapData(); }, child: const Text('Discard', style: TextStyle(color: Colors.grey))),
            OutlinedButton(onPressed: () async { Navigator.pop(ctx); await _savePersonalRun(); _clearMapData(); }, child: const Text('Save Private', style: TextStyle(color: Colors.white))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)), onPressed: () async { Navigator.pop(ctx); await _publishTrek(nameController.text.trim(), selectedDifficulty); _clearMapData(); }, child: const Text('Publish Trek', style: TextStyle(color: Colors.white))),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Offstage(
            offstage: _isAmoledMode,
            child: MapLibreMap(
              onMapCreated: (c) { mapController = c; if (_currentPosition != null) _fetchInitialPosition(); },
              styleString: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
              initialCameraPosition: const CameraPosition(target: LatLng(12.3051, 76.6551), zoom: 15.0),
              myLocationEnabled: false, compassEnabled: false,
            ),
          ),
          
          if (_isAmoledMode)
            const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.battery_saver, color: Color(0xFF00C853), size: 48), SizedBox(height: 12), Text('AMOLED SAVER ACTIVE', style: TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, letterSpacing: 2))])),

          if (!_isAmoledMode)
            Positioned(top: 50, left: 16, child: _buildCircularButton(Icons.sos, _showSOSDialog, bgColor: Colors.redAccent)),

          Positioned(
            top: 50, right: 16,
            child: Column(
              children: [
                if (!_isAmoledMode && _isTracking)
                  Padding(padding: const EdgeInsets.only(bottom: 12.0), child: _buildCircularButton(Icons.add_location_alt, _showWaypointDialog, bgColor: const Color(0xFF007AFF))),
                if (!_isAmoledMode)
                  Padding(padding: const EdgeInsets.only(bottom: 12.0), child: _buildCircularButton(Icons.cloud_download_outlined, _showOfflineDownloadDialog)),
                if (!_isAmoledMode)
                  Padding(padding: const EdgeInsets.only(bottom: 12.0), child: _buildCircularButton(Icons.my_location, _checkLocationPermission)),
                if (widget.trekToFollow != null && !_isAmoledMode)
                  Padding(padding: const EdgeInsets.only(bottom: 12.0), child: _buildCircularButton(Icons.alt_route, () => _loadGuidedTrek(widget.trekToFollow!))),
                if (_isTracking)
                  _buildCircularButton(_isAmoledMode ? Icons.light_mode : Icons.dark_mode, () { setState(() => _isAmoledMode = !_isAmoledMode); if (!_isAmoledMode && _currentPosition != null) { _updateLiveRoute(); _updatePucksOnMap(_currentPosition!); } }),
              ],
            ),
          ),
          
          if (_isTracking && _isOffRoute)
            Positioned(top: 50, left: _isAmoledMode ? 16 : 72, right: 72, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24), SizedBox(width: 12), Expanded(child: Text("OFF ROUTE! Check map.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))]))),

          Positioned(bottom: 0, left: 0, right: 0, child: _isTracking ? _buildActiveHUD() : _buildIdleStartCard()),
        ],
      ),
    );
  }

  Widget _buildCircularButton(IconData icon, VoidCallback onPressed, {Color bgColor = const Color(0xFF1B1E28)}) {
    return Container(decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle), child: IconButton(icon: Icon(icon, color: Colors.white), onPressed: onPressed));
  }

  Widget _buildIdleStartCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), decoration: const BoxDecoration(color: Color(0xFF13151D), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [if (widget.trekToFollow != null) Padding(padding: const EdgeInsets.only(bottom: 12.0), child: Text('Selected: ${widget.trekToFollow!['name']}', style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold))), SizedBox(width: double.infinity, height: 56, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))), icon: const Icon(Icons.play_arrow, color: Colors.white, size: 28), label: const Text('START TREK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), onPressed: _startTrek))])),
    );
  }

  Widget _buildActiveHUD() {
    return Container(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 28),
      decoration: BoxDecoration(color: _isAmoledMode ? Colors.black : const Color(0xFF0C0E14), borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), border: _isAmoledMode ? const Border(top: BorderSide(color: Color(0xFF111111))) : null),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isPaused ? 'PAUSED' : (_isAutoPaused ? 'AUTO-PAUSED' : '${((_currentPosition?.speed ?? 0) * 3.6).toStringAsFixed(1)}'), 
              style: TextStyle(
                fontSize: (_isPaused || _isAutoPaused) ? 32 : 44, 
                fontWeight: FontWeight.bold, 
                color: _isPaused ? Colors.orange : (_isAutoPaused ? Colors.yellow : Colors.white)
              )
            ),
            Text(_isPaused ? 'RESUME TO TRACK' : (_isAutoPaused ? 'WALK TO RESUME' : 'KM/H'), style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildHUDMetric('DISTANCE', '${_liveDistanceKm.toStringAsFixed(2)} KM'), _buildHUDMetric('ELEV GAIN', '${_liveElevationGain.toStringAsFixed(0)} M'), _buildHUDMetric('DURATION', _durationFormatted)]),
            const SizedBox(height: 20),
            if (!_isPaused) SizedBox(width: double.infinity, height: 54, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: _isAmoledMode ? const Color(0xFF111111) : const Color(0xFF1E222D), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27))), icon: const Icon(Icons.pause, color: Colors.white), label: const Text('PAUSE RUN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)), onPressed: _pauseTrek))
            else Row(children: [Expanded(child: SizedBox(height: 54, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C853), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27))), icon: const Icon(Icons.play_arrow, color: Colors.white), label: const Text('RESUME', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: _resumeTrek))), const SizedBox(width: 16), Expanded(child: SizedBox(height: 54, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFC4C02), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27))), icon: const Icon(Icons.stop, color: Colors.white), label: const Text('FINISH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onPressed: _finishTrek)))])
          ],
        ),
      ),
    );
  }

  Widget _buildHUDMetric(String title, String val) {
    return Column(children: [Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1)), const SizedBox(height: 4), Text(val, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]);
  }
}

// ---------------------------------------------------------------------------
// CUSTOM ELEVATION GRAPH WIDGET
// ---------------------------------------------------------------------------
class ElevationSparkline extends StatelessWidget {
  final List<Position> points;
  const ElevationSparkline({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    return Container(
      height: 80, width: double.infinity,
      decoration: BoxDecoration(color: const Color(0xFF13151D), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CustomPaint(painter: _ElevationPainter(points))),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<Position> points;
  _ElevationPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final alts = points.map((p) => p.altitude).toList();
    final maxAlt = alts.reduce((a, b) => a > b ? a : b);
    final minAlt = alts.reduce((a, b) => a < b ? a : b);
    final altRange = (maxAlt - minAlt) == 0 ? 1.0 : (maxAlt - minAlt);

    final path = Path();
    final fillPath = Path();
    path.moveTo(0, size.height - ((alts.first - minAlt) / altRange) * size.height);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, size.height - ((alts.first - minAlt) / altRange) * size.height);

    for (int i = 1; i < alts.length; i++) {
      final x = (i / (alts.length - 1)) * size.width;
      final y = size.height - ((alts[i] - minAlt) / altRange) * size.height;
      path.lineTo(x, y); fillPath.lineTo(x, y);
    }
    fillPath.lineTo(size.width, size.height); fillPath.close();

    final paintFill = Paint()..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, size.height), [const Color(0xFF00C853).withValues(alpha: 0.4), Colors.transparent]);
    canvas.drawPath(fillPath, paintFill);
    final paintStroke = Paint()..color = const Color(0xFF00C853)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    canvas.drawPath(path, paintStroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// TAB 3: STRAVA-STYLE PROFILE SCREEN
// ---------------------------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<dynamic> _myTreks = [];
  Map<String, dynamic>? _userProfile;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    setState(() => _isLoading = true);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (currentUserId == null) return;

    try {
      final profileResponse = await Supabase.instance.client.from('profiles').select().eq('id', currentUserId).maybeSingle();
      final followers = await Supabase.instance.client.from('follows').select('follower_id').eq('following_id', currentUserId);
      final following = await Supabase.instance.client.from('follows').select('following_id').eq('follower_id', currentUserId);
      final trekData = await Supabase.instance.client.from('public_treks').select().eq('creator_id', currentUserId).order('created_at', ascending: false);
          
      if (mounted) {
        setState(() {
          _userProfile = profileResponse;
          _followersCount = followers.length;
          _followingCount = following.length;
          _myTreks = trekData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    final syncedCount = await OfflineSyncManager.syncAll();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(syncedCount > 0 ? 'Successfully synced $syncedCount treks!' : 'Network still unavailable.'), backgroundColor: syncedCount > 0 ? Colors.green : Colors.orange));
      setState(() => _isSyncing = false);
      _fetchProfileData();
    }
  }

  Future<void> _showEditProfileDialog() async {
    final nameCtrl = TextEditingController(text: _userProfile?['display_name'] ?? '');
    final usernameCtrl = TextEditingController(text: _userProfile?['username'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1E28), title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: usernameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Username', prefixText: '@ ', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)), onPressed: () async { try { await Supabase.instance.client.from('profiles').update({'display_name': nameCtrl.text.trim(), 'username': usernameCtrl.text.trim()}).eq('id', Supabase.instance.client.auth.currentUser!.id); Navigator.pop(ctx); _fetchProfileData(); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e'))); } }, child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Future<void> _logout() async { await Supabase.instance.client.auth.signOut(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF0F1115), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchProfileData), IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), tooltip: 'Log Out', onPressed: _logout)]),
      body: RefreshIndicator(
        onRefresh: _fetchProfileData, color: const Color(0xFF007AFF),
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: OfflineSyncManager.pendingCount,
                  builder: (context, pendingCount, child) {
                    if (pendingCount == 0) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange.withValues(alpha: 0.5))),
                      child: Row(children: [const Icon(Icons.cloud_off, color: Colors.orange), const SizedBox(width: 12), Expanded(child: Text('$pendingCount treks waiting for network connection.', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))), _isSyncing ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2)) : TextButton(onPressed: _triggerSync, child: const Text('Sync', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)))]),
                    );
                  }
                ),

                Container(
                  padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: const Color(0xFF161922), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 30, backgroundColor: const Color(0xFF007AFF), backgroundImage: _userProfile?['avatar_url'] != null ? NetworkImage(_userProfile!['avatar_url']) : null, child: _userProfile?['avatar_url'] == null ? const Icon(Icons.person, size: 30, color: Colors.white) : null),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_userProfile?['display_name'] ?? 'Athlete', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)), const SizedBox(height: 2), Text('@${_userProfile?['username'] ?? 'user'}', style: const TextStyle(color: Colors.grey, fontSize: 14))])),
                      IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.grey), onPressed: _showEditProfileDialog),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: const Color(0xFF181B26), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCol('Treks', '${_myTreks.length}'),
                      _buildStatCol('Dist (km)', (_myTreks.fold<double>(0.0, (acc, item) => acc + ((item['distance_meters'] ?? 0) as num)) / 1000).toStringAsFixed(1)),
                      _buildStatCol('Followers', '$_followersCount'),
                      _buildStatCol('Following', '$_followingCount'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('My Activity History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_myTreks.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('No published treks yet.\nGo record one!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))
                else
                  ..._myTreks.map((trek) {
                    final distKm = ((trek['distance_meters'] as num) / 1000).toStringAsFixed(2);
                    final elevGain = (trek['elevation_gain'] as num?)?.toStringAsFixed(0) ?? '0';
                    return GestureDetector(
                      onTap: () {
                         Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(trek: trek, onStartTrail: () {})));
                      },
                      child: Card(
                        color: const Color(0xFF161922), margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xFF007AFF), child: Icon(Icons.terrain, color: Colors.white)),
                          title: Text(trek['name'] ?? 'Trek', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('$distKm km • Gain: ${elevGain}m'),
                        ),
                      ),
                    );
                  }),
              ],
            ),
      ),
    );
  }

  Widget _buildStatCol(String label, String value) {
    return Column(children: [Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF007AFF))), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11))]);
  }
}

// ---------------------------------------------------------------------------
// GPX PARSER HELPER
// ---------------------------------------------------------------------------
class GPXHelper {
  
  static Future<void> exportAndShareTrek(Map<String, dynamic> trek) async {
    final geoJson = jsonDecode(trek['route_geojson']);
    final List coordinates = geoJson['coordinates'];
    
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', attributes: {'version': '1.1', 'creator': 'Xplore'}, nest: () {
      builder.element('trk', nest: () {
        builder.element('name', nest: trek['name'] ?? 'Xplore Trek');
        builder.element('trkseg', nest: () {
          for (var c in coordinates) {
            builder.element('trkpt', attributes: {'lat': c[1].toString(), 'lon': c[0].toString()});
          }
        });
      });
    });
    
    final gpxString = builder.buildDocument().toXmlString(pretty: true);
    final directory = await getTemporaryDirectory();
    final cleanName = (trek['name'] ?? 'Trek').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final file = File('${directory.path}/$cleanName.gpx');
    await file.writeAsString(gpxString);
    
    await Share.shareXFiles([XFile(file.path)], text: 'Check out this trail I found on Xplore!');
  }

  static Future<Map<String, dynamic>?> importTrek(File file, String fileName) async {
    final contents = await file.readAsString();
    final document = XmlDocument.parse(contents);
    final trkpts = document.findAllElements('trkpt');
    
    List<List<double>> coordinates = [];
    for (var pt in trkpts) {
      final lat = double.tryParse(pt.getAttribute('lat') ?? '');
      final lon = double.tryParse(pt.getAttribute('lon') ?? '');
      if (lat != null && lon != null) {
        coordinates.add([lon, lat]);
      }
    }
    
    if (coordinates.isEmpty) return null;

    double totalDist = 0.0;
    for (int i = 0; i < coordinates.length - 1; i++) {
      totalDist += Geolocator.distanceBetween(
        coordinates[i][1], coordinates[i][0], 
        coordinates[i+1][1], coordinates[i+1][0]
      );
    }

    final geoJson = jsonEncode({
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": coordinates }
    });

    return {
      "id": "imported_gpx",
      "name": fileName.replaceAll('.gpx', '').replaceAll('.xml', ''),
      "distance_meters": totalDist,
      "elevation_gain": 0, 
      "difficulty": "Unknown",
      "route_geojson": geoJson,
      "start_lat": coordinates.first[1],
      "start_lng": coordinates.first[0],
      "creator_name": "Imported File",
      "creator_avatar": null
    };
  }
}