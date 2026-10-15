import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart'; 
import 'package:file_picker/file_picker.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:xplore_mobile/screens/trail_detail_screen.dart';
import 'package:xplore_mobile/screens/public_profile_screen.dart';
import 'package:xplore_mobile/widgets/global_search_delegate.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);
const String styleDark = 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';

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
  List<Map<String, dynamic>> _treks = [];
  Set<String> _followingIds = {}; 
  bool _isLoading = true;
  String _feedMode = 'Nearby'; 

  // Advanced Filter States
  String _selectedDifficulty = 'All';
  double _searchRadiusKm = 25.0; 
  double _filterMaxDistanceKm = 50.0; 
  double _filterMaxElevationM = 3000.0; 

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

      final rawTreks = await Supabase.instance.client
          .from('completed_treks')
          .select()
          .order('created_at', ascending: false);

      final creatorIds = rawTreks
          .map((t) => t['user_id']?.toString())
          .where((id) => id != null && id != 'null' && id.trim().isNotEmpty)
          .toSet()
          .toList();
          
      Map<String, dynamic> profileMap = {};
      if (creatorIds.isNotEmpty) {
        final profiles = await Supabase.instance.client.from('profiles').select('id, display_name, avatar_url').inFilter('id', creatorIds);
        profileMap = { for (var p in profiles) p['id'].toString(): p };
      }

      Position? myPos;
      if (_feedMode == 'Nearby') {
        try { 
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
            myPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium); 
          }
        } catch (_) {}
      }

      List<Map<String, dynamic>> mappedTreks = [];
      for (var t in rawTreks) {
        if (t['is_public'] == false) continue;

        final cid = t['user_id']?.toString();
        final profile = profileMap[cid] ?? {};
        
        double? startLat; double? startLng;
        final routeData = t['recorded_route'];
        if (routeData != null) {
          try {
            if (routeData is String && routeData.contains('LINESTRING')) {
               final cleaned = routeData.replaceAll(RegExp(r'SRID=\d+;'), '').replaceAll('LINESTRING(', '').replaceAll(')', '');
               final coords = cleaned.split(',').first.trim().split(RegExp(r'\s+'));
               if (coords.length >= 2) {
                 startLng = double.tryParse(coords[0]);
                 startLat = double.tryParse(coords[1]);
               }
            } else {
              dynamic parsed = routeData is String ? jsonDecode(routeData) : routeData;
              if (parsed is List && parsed.isNotEmpty) {
                final first = parsed.first;
                if (first is Map) { startLat = (first['lat'] as num).toDouble(); startLng = (first['lng'] as num).toDouble(); }
                else if (first is List && first.length >= 2) { startLat = (first[1] as num).toDouble(); startLng = (first[0] as num).toDouble(); }
              } else if (parsed is Map) {
                 final coords = parsed['coordinates'] ?? parsed['geometry']?['coordinates'] ?? [];
                 if (coords.isNotEmpty && coords.first is List && coords.first.length >= 2) {
                   startLng = (coords.first[0] as num).toDouble();
                   startLat = (coords.first[1] as num).toDouble();
                 }
              }
            }
          } catch (_) {}
        }

        if (_feedMode == 'Following') {
          if (!_followingIds.contains(cid) && cid != userId) continue;
        } else if (_feedMode == 'Nearby') {
          if (myPos != null && startLat != null && startLng != null) {
            final distToTrek = Geolocator.distanceBetween(myPos.latitude, myPos.longitude, startLat, startLng);
            if (distToTrek > (_searchRadiusKm * 1000)) continue; 
          }
        }

        mappedTreks.add({
          ...t,
          'id': t['id'],
          'creator_id': cid ?? '',
          'creator_name': profile['display_name'] ?? 'Athlete',
          'creator_avatar': profile['avatar_url'],
          'name': t['trek_name'] ?? 'Wilderness Trek',
          'distance_meters': (double.tryParse(t['distance']?.toString() ?? '0') ?? 0) * 1000,
          'elevation_gain': double.tryParse(t['elevation_gain']?.toString() ?? '0') ?? 0,
          'route_geom': routeData,
        });
      }

      if (mounted) setState(() { _treks = mappedTreks; _isLoading = false; });
    } catch (e) {
      debugPrint("Fetch Data Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(String targetUserId) async {
    if (targetUserId.isEmpty || targetUserId == 'null') return;
    
    HapticFeedback.lightImpact();
    final myId = Supabase.instance.client.auth.currentUser!.id;
    final isCurrentlyFollowing = _followingIds.contains(targetUserId);

    setState(() {
      if (isCurrentlyFollowing) _followingIds.remove(targetUserId);
      else _followingIds.add(targetUserId);
    });

    try {
      if (isCurrentlyFollowing) {
        await Supabase.instance.client.from('follows').delete().eq('follower_id', myId).eq('following_id', targetUserId);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unfollowed athlete'), duration: Duration(seconds: 1)));
      } else {
        await Supabase.instance.client.from('follows').insert({'follower_id': myId, 'following_id': targetUserId});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are now following this athlete!'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
      }
    } catch (e) {
      setState(() { 
        if (isCurrentlyFollowing) _followingIds.add(targetUserId);
        else _followingIds.remove(targetUserId);
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update follow status: $e'), backgroundColor: Colors.redAccent));
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context, backgroundColor: cardSurface, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Advanced Filters', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () {
                      setSheetState(() { _selectedDifficulty = 'All'; _filterMaxDistanceKm = 50.0; _filterMaxElevationM = 3000.0; });
                      setState(() { _selectedDifficulty = 'All'; _filterMaxDistanceKm = 50.0; _filterMaxElevationM = 3000.0; });
                    },
                    child: const Text('Reset', style: TextStyle(color: neonAccent, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
              const SizedBox(height: 16),
              
              const Text('Difficulty', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['All', 'Easy', 'Moderate', 'Hard'].map((diff) {
                  final isSelected = _selectedDifficulty == diff;
                  return ChoiceChip(
                    label: Text(diff), selected: isSelected, selectedColor: neonAccent,
                    backgroundColor: bgColor, labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                    onSelected: (val) { setSheetState(() => _selectedDifficulty = diff); setState(() => _selectedDifficulty = diff); },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Max Distance', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), Text('${_filterMaxDistanceKm.toStringAsFixed(0)} km', style: const TextStyle(color: neonAccent, fontWeight: FontWeight.bold))]),
              Slider(value: _filterMaxDistanceKm, min: 1.0, max: 100.0, activeColor: neonAccent, inactiveColor: Colors.grey[800], onChanged: (val) { setSheetState(() => _filterMaxDistanceKm = val); setState(() => _filterMaxDistanceKm = val); }),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Max Elevation', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), Text('${_filterMaxElevationM.toStringAsFixed(0)} m', style: const TextStyle(color: neonAccent, fontWeight: FontWeight.bold))]),
              Slider(value: _filterMaxElevationM, min: 100.0, max: 5000.0, activeColor: neonAccent, inactiveColor: Colors.grey[800], onChanged: (val) { setSheetState(() => _filterMaxElevationM = val); setState(() => _filterMaxElevationM = val); }),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.pop(ctx), child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
            ],
          ),
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Discover', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), 
        backgroundColor: bgColor, elevation: 0, iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.search), 
            tooltip: 'Search', 
            onPressed: () => showSearch(
              context: context, 
              delegate: GlobalSearchDelegate(
                onSelectTrek: widget.onSelectTrek,
                searchType: 'public_trails',
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Filters', onPressed: _showFilterSheet),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ]
      ),
      body: RefreshIndicator(
        onRefresh: _fetchData, color: neonAccent, backgroundColor: cardSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(child: GestureDetector(onTap: () { setState(() { _feedMode = 'Nearby'; _isLoading = true; }); _fetchData(); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _feedMode == 'Nearby' ? neonAccent : Colors.transparent, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('Nearby Trails', style: TextStyle(fontWeight: FontWeight.bold, color: _feedMode == 'Nearby' ? Colors.black : Colors.grey))))),
                  Expanded(child: GestureDetector(onTap: () { setState(() { _feedMode = 'Following'; _isLoading = true; }); _fetchData(); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _feedMode == 'Following' ? neonAccent : Colors.transparent, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('Following', style: TextStyle(fontWeight: FontWeight.bold, color: _feedMode == 'Following' ? Colors.black : Colors.grey))))),
                ],
              ),
            ),
            
            if (_feedMode == 'Nearby')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Search Radius', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)), Text('${_searchRadiusKm.toStringAsFixed(0)} KM', style: const TextStyle(color: neonAccent, fontWeight: FontWeight.bold, fontSize: 15))]), Slider(value: _searchRadiusKm, min: 5.0, max: 150.0, divisions: 29, activeColor: neonAccent, inactiveColor: Colors.grey[800], onChanged: (val) => setState(() => _searchRadiusKm = val), onChangeEnd: (val) => _fetchData())]),
              ),

            Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Text('${filtered.length} trails matching filters', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600))),
            
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: neonAccent)) 
                : filtered.isEmpty 
                  ? ListView(children: [const SizedBox(height: 100), Center(child: Text(_feedMode == 'Nearby' ? 'No treks found nearby.\nTry expanding your radius or clearing filters!' : 'No treks yet.\nStart following other athletes!', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)))]) 
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final trek = filtered[index];
                        final creatorId = trek['creator_id']?.toString() ?? '';
                        final isMyTrek = creatorId == myId;
                        final isFollowing = _followingIds.contains(creatorId);

                        return _ExploreTrailCard(
                          trek: trek,
                          isMyTrek: isMyTrek,
                          isFollowing: isFollowing,
                          onToggleFollow: () => _toggleFollow(creatorId),
                          onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(trek: trek, onStartTrail: () => widget.onSelectTrek(trek)))); },
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
// VERTICAL EXPLORE CARD WIDGET WITH MAP OVERVIEW SUPPORT (CRASH-PROOF)
// ---------------------------------------------------------------------------
class _ExploreTrailCard extends StatefulWidget {
  final Map<String, dynamic> trek;
  final bool isMyTrek;
  final bool isFollowing;
  final VoidCallback onToggleFollow;
  final VoidCallback onTap;

  const _ExploreTrailCard({
    required this.trek, required this.isMyTrek, required this.isFollowing, required this.onToggleFollow, required this.onTap
  });

  @override
  State<_ExploreTrailCard> createState() => _ExploreTrailCardState();
}

class _ExploreTrailCardState extends State<_ExploreTrailCard> {
  MapLibreMapController? _mapController;

  void _onStyleLoaded() async {
    if (_mapController == null) return;
    try {
      List<LatLng> pts = [];
      final routeData = widget.trek['route_geom'] ?? widget.trek['route_geojson'];
      if (routeData == null) return;

      if (routeData is String) {
        if (routeData.startsWith('0102') || routeData.startsWith('0101')) return; 
        if (routeData.contains('LINESTRING')) {
          final cleaned = routeData.replaceAll(RegExp(r'SRID=\d+;'), '').replaceAll('LINESTRING(', '').replaceAll(')', '');
          final pairs = cleaned.split(',');
          for (var pair in pairs) {
            final coords = pair.trim().split(RegExp(r'\s+'));
            if (coords.length >= 2) pts.add(LatLng(double.parse(coords[1]), double.parse(coords[0])));
          }
        } else {
          final decoded = jsonDecode(routeData);
          final coordinates = decoded['coordinates'] ?? decoded['geometry']?['coordinates'] ?? [];
          pts = coordinates.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        }
      } else if (routeData is Map) {
        final coordinates = routeData['coordinates'] ?? routeData['geometry']?['coordinates'] ?? [];
        pts = coordinates.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      } else if (routeData is List) {
        pts = routeData.map<LatLng>((p) => p is Map ? LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()) : LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
      }

      if (pts.isNotEmpty) {
        List<List<double>> coords = pts.map((p) => [p.longitude, p.latitude]).toList();
        final routeGeoJson = {
          "type": "FeatureCollection",
          "features": [{"type": "Feature", "properties": {}, "geometry": {"type": "LineString", "coordinates": coords}}]
        };

        await _mapController!.addSource("route-source", GeojsonSourceProperties(data: routeGeoJson));
        await _mapController!.addLineLayer("route-source", "route-layer", const LineLayerProperties(lineColor: "#D4FF00", lineWidth: 5.0, lineCap: "round", lineJoin: "round"));

        double minLat = pts.first.latitude, maxLat = pts.first.latitude;
        double minLng = pts.first.longitude, maxLng = pts.first.longitude;
        for (var p in pts) {
          if (p.latitude < minLat) minLat = p.latitude; if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude; if (p.longitude > maxLng) maxLng = p.longitude;
        }

        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 
          top: 30, bottom: 30, left: 30, right: 30
        ));
      }
    } catch (e) {
      debugPrint("Explore card map error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final distKm = (double.tryParse(widget.trek['distance']?.toString() ?? (widget.trek['distance_meters']?.toString() ?? '0')) ?? 0.0);
    final elevM = (double.tryParse(widget.trek['elevation_gain']?.toString() ?? '0') ?? 0.0);
    final difficulty = widget.trek['difficulty'] ?? 'Moderate';
    Color badgeColor = difficulty == 'Hard' ? Colors.redAccent : (difficulty == 'Easy' ? Colors.green : Colors.orangeAccent);

    final estHours = (distKm / 5.0) + (elevM / 600.0);
    final estTimeStr = estHours < 1.0 ? '${(estHours * 60).round()} mins' : '${estHours.floor()}h ${((estHours % 1) * 60).round()}m';

    final imageUrl = widget.trek['image_url'];
    final creatorName = widget.trek['creator_name'] ?? 'Athlete';
    final creatorAvatar = widget.trek['creator_avatar'];
    final creatorId = widget.trek['creator_id'] ?? '';
    
    final bool isValidProfile = creatorId.isNotEmpty && creatorId != 'null' && creatorId.length > 10;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 250, margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ShaderMask(
                shaderCallback: (rect) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.95)], stops: const [0.2, 1.0]).createShader(rect),
                blendMode: BlendMode.darken,
                child: (imageUrl != null && imageUrl.toString().isNotEmpty)
                  ? Image.network(imageUrl, height: double.infinity, width: double.infinity, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: bgColor, child: const Icon(Icons.terrain, color: Colors.white24, size: 48)))
                  : AbsorbPointer(
                      child: MapLibreMap(
                        onMapCreated: (controller) => _mapController = controller,
                        onStyleLoadedCallback: _onStyleLoaded,
                        styleString: styleDark,
                        initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 2),
                        myLocationEnabled: false, compassEnabled: false,
                      ),
                    ),
              ),
            ),
            
            Positioned(
              top: 16, left: 16, right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () { if (isValidProfile && creatorId != 'my_android_device') Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(userId: creatorId))); },
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: neonAccent, width: 1.5)), child: CircleAvatar(radius: 14, backgroundImage: creatorAvatar != null ? NetworkImage(creatorAvatar) : null, backgroundColor: Colors.grey[800], child: creatorAvatar == null ? const Icon(Icons.person, size: 16, color: Colors.white) : null)), 
                      const SizedBox(width: 8), 
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)), child: Text(creatorName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)))
                    ]),
                  ),  
                  if (!widget.isMyTrek && isValidProfile)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onToggleFollow, 
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), 
                        decoration: BoxDecoration(color: widget.isFollowing ? Colors.black.withValues(alpha: 0.6) : neonAccent, border: widget.isFollowing ? Border.all(color: Colors.white30) : null, borderRadius: BorderRadius.circular(16)), 
                        child: Text(widget.isFollowing ? 'Following' : 'Follow', style: TextStyle(color: widget.isFollowing ? Colors.white : Colors.black, fontSize: 12, fontWeight: FontWeight.bold))
                      )
                    )
                ],
              ),
            ),

            Positioned(
              bottom: 16, left: 16, right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.trek['name'] ?? 'Wilderness Trek', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMiniStat(Icons.straighten, '${(distKm).toStringAsFixed(1)} km'),
                        _buildMiniStat(Icons.trending_up, '${elevM.toStringAsFixed(0)} m'),
                        _buildMiniStat(Icons.timer_outlined, estTimeStr),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: badgeColor.withValues(alpha: 0.5))), child: Text(difficulty, style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value) {
    return Row(children: [Icon(icon, color: neonAccent, size: 16), const SizedBox(width: 6), Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))]);
  }
}

// ---------------------------------------------------------------------------
// GPX PARSER HELPER (Unchanged)
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