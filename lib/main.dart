import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
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

// --- YOUR NEW MODULAR SCREENS ---
import 'package:xplore_mobile/screens/my_dashboard_screen.dart' hide PublicProfileScreen;
import 'package:xplore_mobile/screens/live_trek_hud_screen.dart';
import 'package:xplore_mobile/screens/trail_detail_screen.dart';
import 'package:xplore_mobile/screens/public_profile_screen.dart';
import 'package:xplore_mobile/services/tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeTrackingService();

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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
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
          LiveTrekHudScreen(trekToFollow: _selectedTrekToFollow),
          MyDashboardScreen(onSelectTrek: _onSelectTrekFromExplore),
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

      // --- 🌟 STITCH PROFILE DATA INTO TREKS ---
      if (data.isNotEmpty) {
        // 1. Gather all unique creator IDs from the trails
        final creatorIds = data.map((t) => t['creator_id'].toString()).where((id) => id.isNotEmpty && id != 'my_android_device').toSet().toList();
        
        if (creatorIds.isNotEmpty) {
          // 2. Fetch all matching profiles in one fast batch query
          final profiles = await Supabase.instance.client.from('profiles').select('id, display_name, avatar_url').inFilter('id', creatorIds);
          
          // 3. Create a quick lookup map (explicitly forcing String keys for safety)
          final profileMap = { for (var p in profiles) p['id'].toString(): p };
          
          // 4. Inject the real names and avatars into the trail data
          data = data.map((trek) {
            final cid = trek['creator_id']?.toString();
            if (cid != null && profileMap.containsKey(cid)) {
              // Safely extract the profile object first to satisfy Dart null-safety
              final profile = profileMap[cid]!; 
              trek['creator_name'] = profile['display_name'] ?? 'Athlete';
              trek['creator_avatar'] = profile['avatar_url'];
            }
            return trek;
          }).toList();
        }
      }
      // ------------------------------------------

      if (mounted) setState(() { _treks = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importGPX() async {
    try {
      final PlatformFile? pickedFile = await FilePicker.pickFile(
        type: FileType.custom, 
        allowedExtensions: ['gpx', 'xml'],
      );

      if (pickedFile != null && pickedFile.path != null) {
        final File file = File(pickedFile.path!);
        final importedTrek = await GPXHelper.importTrek(file, pickedFile.name);

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
    } catch (_) {
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
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      if (creatorId.isNotEmpty && creatorId != 'my_android_device') {
                                        Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(userId: creatorId)));
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        CircleAvatar(radius: 14, backgroundImage: creatorAvatar != null ? NetworkImage(creatorAvatar) : null, backgroundColor: const Color(0xFF007AFF), child: creatorAvatar == null ? const Icon(Icons.person, size: 14, color: Colors.white) : null),
                                        const SizedBox(width: 8),
                                        Flexible(child: Text(creatorName, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  ),
                                ),  
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