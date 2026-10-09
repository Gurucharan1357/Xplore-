import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart'; 
import 'package:file_picker/file_picker.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'package:path_provider/path_provider.dart'; 

import 'package:xplore_mobile/screens/trail_detail_screen.dart';
import 'package:xplore_mobile/screens/public_profile_screen.dart';

// ---------------------------------------------------------------------------
// EXPLORE SCREEN
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
  String _feedMode = 'Nearby'; 

  // Advanced Filter States
  String _selectedDifficulty = 'All';
  double _searchRadiusKm = 25.0; // For fetching Nearby
  double _filterMaxDistanceKm = 50.0; // For local filtering
  double _filterMaxElevationM = 3000.0; // For local filtering

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

      // Stitch Profiles
      if (data.isNotEmpty) {
        final creatorIds = data.map((t) => t['creator_id'].toString()).where((id) => id.isNotEmpty && id != 'my_android_device').toSet().toList();
        if (creatorIds.isNotEmpty) {
          final profiles = await Supabase.instance.client.from('profiles').select('id, display_name, avatar_url').inFilter('id', creatorIds);
          final profileMap = { for (var p in profiles) p['id'].toString(): p };
          data = data.map((trek) {
            final cid = trek['creator_id']?.toString();
            if (cid != null && profileMap.containsKey(cid)) {
              final profile = profileMap[cid]!; 
              trek['creator_name'] = profile['display_name'] ?? 'Athlete';
              trek['creator_avatar'] = profile['avatar_url'];
            }
            return trek;
          }).toList();
        }
      }

      if (mounted) setState(() { _treks = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
      setState(() { // Revert on failure
        if (isCurrentlyFollowing) _followingIds.add(targetUserId);
        else _followingIds.remove(targetUserId);
      });
    }
  }

  // --- ADVANCED FILTER BOTTOM SHEET ---
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF161922), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Advanced Filters', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              const Text('Difficulty', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['All', 'Easy', 'Moderate', 'Hard'].map((diff) {
                  final isSelected = _selectedDifficulty == diff;
                  return ChoiceChip(
                    label: Text(diff), selected: isSelected, selectedColor: const Color(0xFF007AFF).withValues(alpha: 0.3),
                    backgroundColor: const Color(0xFF1E222D), labelStyle: TextStyle(color: isSelected ? const Color(0xFF007AFF) : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                    onSelected: (val) { setSheetState(() => _selectedDifficulty = diff); setState(() => _selectedDifficulty = diff); },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Max Distance', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), Text('${_filterMaxDistanceKm.toStringAsFixed(0)} km', style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold))]),
              Slider(value: _filterMaxDistanceKm, min: 1.0, max: 100.0, activeColor: const Color(0xFF007AFF), inactiveColor: Colors.grey[800], onChanged: (val) { setSheetState(() => _filterMaxDistanceKm = val); setState(() => _filterMaxDistanceKm = val); }),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Max Elevation', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), Text('${_filterMaxElevationM.toStringAsFixed(0)} m', style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold))]),
              Slider(value: _filterMaxElevationM, min: 100.0, max: 5000.0, activeColor: const Color(0xFF007AFF), inactiveColor: Colors.grey[800], onChanged: (val) { setSheetState(() => _filterMaxElevationM = val); setState(() => _filterMaxElevationM = val); }),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.pop(ctx), child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
            ],
          ),
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    // Apply local filters
    final filtered = _treks.where((t) {
      final distKm = ((t['distance_meters'] ?? 0) as num) / 1000;
      final elevM = ((t['elevation_gain'] ?? 0) as num);
      final diff = t['difficulty'] ?? 'Moderate';
      
      bool diffMatch = _selectedDifficulty == 'All' || diff == _selectedDifficulty;
      bool distMatch = distKm <= _filterMaxDistanceKm;
      bool elevMatch = elevM <= _filterMaxElevationM;
      return diffMatch && distMatch && elevMatch;
    }).toList();

    final myId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover', style: TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: const Color(0xFF0F1115), 
        actions: [
          // USER SEARCH ICON
          IconButton(icon: const Icon(Icons.search), tooltip: 'Search Athletes', onPressed: () {
            showSearch(context: context, delegate: UserSearchDelegate());
          }),
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Filters', onPressed: _showFilterSheet),
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
                  Expanded(child: GestureDetector(onTap: () { setState(() { _feedMode = 'Nearby'; _isLoading = true; }); _fetchData(); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _feedMode == 'Nearby' ? const Color(0xFF007AFF) : Colors.transparent, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('Nearby Trails', style: TextStyle(fontWeight: FontWeight.bold, color: _feedMode == 'Nearby' ? Colors.white : Colors.grey))))),
                  Expanded(child: GestureDetector(onTap: () { setState(() { _feedMode = 'Following'; _isLoading = true; }); _fetchData(); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _feedMode == 'Following' ? const Color(0xFF007AFF) : Colors.transparent, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('Following', style: TextStyle(fontWeight: FontWeight.bold, color: _feedMode == 'Following' ? Colors.white : Colors.grey))))),
                ],
              ),
            ),
            
            if (_feedMode == 'Nearby')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8), decoration: BoxDecoration(color: const Color(0xFF161922), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Search Radius', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)), Text('${_searchRadiusKm.toStringAsFixed(0)} KM', style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold, fontSize: 15))]), Slider(value: _searchRadiusKm, min: 5.0, max: 150.0, divisions: 29, activeColor: const Color(0xFF007AFF), inactiveColor: Colors.grey[800], onChanged: (val) => setState(() => _searchRadiusKm = val), onChangeEnd: (val) => _fetchData())]),
              ),

            Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Text('${filtered.length} trails matching filters', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600))),
            
            Expanded(
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : filtered.isEmpty ? ListView(children: [const SizedBox(height: 100), Center(child: Text(_feedMode == 'Nearby' ? 'No treks found nearby.\nTry expanding your radius or clearing filters!' : 'No treks yet.\nStart following other athletes!', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)))]) : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final trek = filtered[index];
                  final distanceKm = ((trek['distance_meters'] as num) / 1000).toDouble();
                  final elevGain = ((trek['elevation_gain'] as num?) ?? 0).toDouble();
                  final difficulty = trek['difficulty'] ?? 'Moderate';
                  final creatorId = trek['creator_id']?.toString() ?? '';
                  final creatorName = trek['creator_name'] ?? 'Athlete';
                  final creatorAvatar = trek['creator_avatar'];

                  // Estimated Time Formula: 5km/h base pace + 30 mins per 300m elevation gain
                  final estHours = (distanceKm / 5.0) + (elevGain / 600.0);
                  final estTimeStr = estHours < 1.0 ? '${(estHours * 60).round()} mins' : '${estHours.floor()}h ${((estHours % 1) * 60).round()}m';

                  Color badgeColor = difficulty == 'Hard' ? Colors.redAccent : (difficulty == 'Easy' ? Colors.green : Colors.orangeAccent);
                  final isMyTrek = creatorId == myId;
                  final isFollowing = _followingIds.contains(creatorId);

                  return GestureDetector(
                    onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(trek: trek, onStartTrail: () => widget.onSelectTrek(trek)))); },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: const Color(0xFF1A1D27), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () { if (creatorId.isNotEmpty && creatorId != 'my_android_device') Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(userId: creatorId))); },
                                    child: Row(children: [CircleAvatar(radius: 16, backgroundImage: creatorAvatar != null ? NetworkImage(creatorAvatar) : null, backgroundColor: const Color(0xFF007AFF), child: creatorAvatar == null ? const Icon(Icons.person, size: 16, color: Colors.white) : null), const SizedBox(width: 12), Flexible(child: Text(creatorName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))]),
                                  ),
                                ),  
                                if (!isMyTrek)
                                  GestureDetector(onTap: () => _toggleFollow(creatorId), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: isFollowing ? Colors.transparent : const Color(0xFF007AFF), border: isFollowing ? Border.all(color: Colors.grey) : null, borderRadius: BorderRadius.circular(16)), child: Text(isFollowing ? 'Following' : 'Follow', style: TextStyle(color: isFollowing ? Colors.white70 : Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))
                              ],
                            ),
                            const Divider(color: Colors.white10, height: 24),
                            
                            Text(trek['name'] ?? 'Wilderness Trek', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                            const SizedBox(height: 12),
                            
                            Container(
                              padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF0F1115), borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildMiniStat(Icons.straighten, '${distanceKm.toStringAsFixed(1)} km'),
                                  _buildMiniStat(Icons.trending_up, '${elevGain.toStringAsFixed(0)} m'),
                                  _buildMiniStat(Icons.timer_outlined, estTimeStr),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text(difficulty, style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            )
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

  Widget _buildMiniStat(IconData icon, String value) {
    return Row(children: [Icon(icon, color: const Color(0xFF007AFF), size: 16), const SizedBox(width: 4), Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold))]);
  }
}

// ---------------------------------------------------------------------------
// GLOBAL USER SEARCH DELEGATE
// ---------------------------------------------------------------------------
class UserSearchDelegate extends SearchDelegate<String> {
  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0F1115), elevation: 0),
      scaffoldBackgroundColor: const Color(0xFF0F1115),
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey)),
      textTheme: const TextTheme(titleLarge: TextStyle(color: Colors.white, fontSize: 18)),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: Color(0xFF007AFF)),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () => query = '')
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => close(context, ''));
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(child: Text('Search for athletes by name or username', style: TextStyle(color: Colors.grey)));
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Supabase.instance.client.from('profiles').select().or('display_name.ilike.%${query.trim()}%,username.ilike.%${query.trim()}%').limit(20),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)));
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
        
        final results = snapshot.data ?? [];
        if (results.isEmpty) return const Center(child: Text('No athletes found.', style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final user = results[index];
            final avatarUrl = user['avatar_url'];
            final displayName = user['display_name'] ?? 'Athlete';
            final username = user['username'] != null ? '@${user['username']}' : '';
            final userId = user['id'];

            if (userId == Supabase.instance.client.auth.currentUser?.id) return const SizedBox.shrink();

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF007AFF), backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null,
              ),
              title: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(username, style: const TextStyle(color: Colors.grey)),
              onTap: () {
                close(context, '');
                Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(userId: userId)));
              },
            );
          },
        );
      },
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