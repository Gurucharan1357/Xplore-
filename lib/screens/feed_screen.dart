import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:xplore_mobile/screens/trail_detail_screen.dart';
import 'package:xplore_mobile/screens/public_profile_screen.dart';
import 'package:xplore_mobile/screens/notifications_screen.dart'; 
import 'package:xplore_mobile/widgets/global_search_delegate.dart'; 

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<dynamic> _feedItems = [];
  bool _isLoading = true;
  int _unreadNotifications = 0; 

  @override
  void initState() {
    super.initState();
    _fetchFeed();
    _checkUnreadNotifications();
  }

  Future<void> _checkUnreadNotifications() async {
    try {
      final myId = Supabase.instance.client.auth.currentUser!.id;
      final res = await Supabase.instance.client
          .from('user_notifications')
          .select('id')
          .eq('user_id', myId)
          .eq('is_read', false);
          
      if (mounted) setState(() => _unreadNotifications = res.length);
    } catch (_) {}
  }

  Future<void> _fetchFeed() async {
    setState(() => _isLoading = true);
    try {
      final myId = Supabase.instance.client.auth.currentUser!.id;

      final followsRes = await Supabase.instance.client
          .from('follows') 
          .select('following_id')
          .eq('follower_id', myId);
          
      List<String> followingIds = [];
      for (var row in followsRes) {
        followingIds.add(row['following_id']);
      }

      followingIds.add(myId); 
      
      final response = await Supabase.instance.client
          .from('completed_treks')
          .select('*, profiles:user_id(display_name, avatar_url)')
          .inFilter('user_id', followingIds)
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .limit(20);

      if (mounted) {
        setState(() {
          _feedItems = response;
        });
      }
    } catch (e) {
      debugPrint('Error fetching feed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _formatTrekForDetail(Map<String, dynamic> item) {
    final profile = item['profiles'] ?? {};
    final Map<String, dynamic> safeMap = Map<String, dynamic>.from(item);
    
    safeMap['id'] = item['id'];
    safeMap['name'] = item['trek_name'] ?? 'Wilderness Trek';
    safeMap['distance_meters'] = (double.tryParse(item['distance']?.toString() ?? '0') ?? 0) * 1000;
    safeMap['elevation_gain'] = double.tryParse(item['elevation_gain']?.toString() ?? '0') ?? 0;
    safeMap['route_geom'] = item['recorded_route'] ?? item['route_geom'];
    safeMap['creator_id'] = item['user_id'];
    safeMap['creator_name'] = profile['display_name'] ?? 'Athlete';
    safeMap['creator_avatar'] = profile['avatar_url'];
    
    return safeMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text('Xplore Feed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: -0.5)),
        actions: [
          // 1. Search Feed Trails
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              showSearch(
                context: context, 
                delegate: GlobalSearchDelegate(
                  searchType: 'feed_trails',
                  onSelectTrek: (trek) {} 
                )
              );
            },
          ),
          // 2. Add User / Search Athletes
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
            onPressed: () {
              showSearch(
                context: context, 
                delegate: GlobalSearchDelegate(
                  searchType: 'athletes',
                  onSelectTrek: (trek) {} 
                )
              );
            },
          ),
          // 3. Notifications
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                  _checkUnreadNotifications(); 
                },
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    child: Text('$_unreadNotifications', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                )
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: neonAccent))
          : _feedItems.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: Colors.black,
                  backgroundColor: neonAccent,
                  onRefresh: () async {
                    await _fetchFeed();
                    await _checkUnreadNotifications();
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 8, bottom: 100),
                    itemCount: _feedItems.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      return _buildFeedCard(_feedItems[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terrain, size: 80, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text("Your feed is quiet.", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Search and follow athletes to get started.", style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> item) {
    final profile = item['profiles'] ?? {};
    final displayName = profile['display_name'] ?? 'Unknown Athlete';
    final avatarUrl = profile['avatar_url'];
    final userId = item['user_id'];
    
    final trekName = item['trek_name'] ?? 'Freestyle Walk';
    final description = item['description'] ?? '';
    final imageUrl = item['image_url'];
    
    final distance = item['distance']?.toString() ?? '0.00';
    final pace = item['pace']?.toString() ?? '--:--';
    final duration = item['duration']?.toString() ?? '00:00:00';
    final elevation = item['elevation_gain']?.toString() ?? '0';

    DateTime createdAt = DateTime.now();
    if (item['created_at'] != null) {
      createdAt = DateTime.tryParse(item['created_at']) ?? DateTime.now();
    }
    final timeAgo = timeago.format(createdAt);

    return GestureDetector(
      onTap: () {
        final formattedTrek = _formatTrekForDetail(item);
        Navigator.push(context, MaterialPageRoute(builder: (_) => TrailDetailScreen(trek: formattedTrek, onStartTrail: () {})));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (userId != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: userId)));
                      }
                    },
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl == null ? const Icon(Icons.person, color: Colors.white54) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (userId != null) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: userId)));
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(timeAgo, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.more_horiz, color: Colors.grey), onPressed: () {})
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trekName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (description.isNotEmpty && description != 'null') ...[
                    const SizedBox(height: 6),
                    Text(description, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 220,
              width: double.infinity,
              color: bgColor,
              child: (imageUrl != null && imageUrl.toString().isNotEmpty && !imageUrl.toString().contains('unsplash.com'))
                  ? Image.network(imageUrl, fit: BoxFit.cover)
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(opacity: 0.05, child: CustomPaint(painter: GridPainter(), size: Size.infinite)),
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: CustomPaint(
                            painter: RouteMiniPainter(routeData: item['recorded_route'] ?? item['route_geom'], color: neonAccent),
                            size: Size.infinite,
                          ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatColumn('Distance', '$distance km'),
                  _buildStatColumn('Pace', '$pace /km'),
                  _buildStatColumn('Time', duration),
                  _buildStatColumn('Elevation', '$elevation m'),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  TextButton.icon(onPressed: () {}, icon: const Icon(Icons.thumb_up_outlined, color: Colors.grey, size: 20), label: const Text('Kudos', style: TextStyle(color: Colors.grey))),
                  TextButton.icon(onPressed: () {}, icon: const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 20), label: const Text('Comment', style: TextStyle(color: Colors.grey))),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.share_outlined, color: Colors.grey, size: 20), onPressed: () {}),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HIGH PERFORMANCE ROUTE PAINTER FOR FEED CARDS
// ---------------------------------------------------------------------------
class RouteMiniPainter extends CustomPainter {
  final dynamic routeData;
  final Color color;
  
  RouteMiniPainter({required this.routeData, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (routeData == null) return;
    List<Offset> rawPoints = [];

    if (routeData is String) {
      if (routeData.contains('LINESTRING')) {
        final cleaned = routeData.replaceAll(RegExp(r'SRID=\d+;'), '').replaceAll('LINESTRING(', '').replaceAll(')', '');
        final pairs = cleaned.split(',');
        for (var pair in pairs) {
          final coords = pair.trim().split(RegExp(r'\s+'));
          if (coords.length >= 2) {
            final lon = double.tryParse(coords[0]);
            final lat = double.tryParse(coords[1]);
            if (lon != null && lat != null) rawPoints.add(Offset(lon, lat));
          }
        }
      } else {
        try { 
          final decoded = jsonDecode(routeData); 
          final coordinates = decoded['coordinates'] ?? decoded['geometry']?['coordinates'] ?? [];
          for (var c in coordinates) { if (c is List && c.length >= 2) rawPoints.add(Offset((c[0] as num).toDouble(), (c[1] as num).toDouble())); }
        } catch (_) {}
      }
    } else if (routeData is List) {
      for (var p in routeData) {
        if (p is Map) {
          final lat = (p['lat'] as num?)?.toDouble();
          final lng = (p['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) rawPoints.add(Offset(lng, lat));
        }
      }
    }

    if (rawPoints.isEmpty) return;

    double minLng = double.infinity, maxLng = -double.infinity;
    double minLat = double.infinity, maxLat = -double.infinity;
    for (var p in rawPoints) {
      if (p.dx < minLng) minLng = p.dx; if (p.dx > maxLng) maxLng = p.dx;
      if (p.dy < minLat) minLat = p.dy; if (p.dy > maxLat) maxLat = p.dy;
    }

    if (minLng == maxLng || minLat == maxLat) return;

    final path = Path();
    bool isFirst = true;

    for (var p in rawPoints) {
      final normalizedX = (p.dx - minLng) / (maxLng - minLng);
      final normalizedY = 1.0 - ((p.dy - minLat) / (maxLat - minLat)); 
      
      final x = normalizedX * size.width;
      final y = normalizedY * size.height;
      
      if (isFirst) {
        path.moveTo(x, y);
        isFirst = false;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, Paint()..color = color.withOpacity(0.3)..strokeWidth = 6.0..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 3.0..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 40) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 40) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}