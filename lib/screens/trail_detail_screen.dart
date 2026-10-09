import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xplore_mobile/main.dart'; 

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

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
  List<Map<String, dynamic>> _gallery = [];
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
      
      try {
        final galleryRes = await Supabase.instance.client.from('trek_gallery').select().eq('trek_id', trekId).order('created_at', ascending: false);
        _gallery = List<Map<String, dynamic>>.from(galleryRes);
      } catch (e) {
        debugPrint('Gallery table missing or error: $e');
      }
      
      if (mounted) setState(() { _comments = commentsRes; _isLoadingSocial = false; });
    } catch(e) {
      if (mounted) setState(() => _isLoadingSocial = false);
    }
  }

  Future<void> _uploadGalleryPhoto() async {
    if (widget.trek['id'] == 'imported_gpx') return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;

    setState(() => _isLoadingSocial = true);
    
    try {
      final file = File(image.path);
      final ext = image.path.split('.').last.toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${widget.trek['id']}.$ext';

      await Supabase.instance.client.storage.from('TrailImages').upload(fileName, file);
      final publicUrl = Supabase.instance.client.storage.from('TrailImages').getPublicUrl(fileName);

      await Supabase.instance.client.from('trek_gallery').insert({
        'trek_id': widget.trek['id'],
        'user_id': Supabase.instance.client.auth.currentUser!.id,
        'image_url': publicUrl
      });

      final currentCover = widget.trek['image_url'] ?? '';
      if (currentCover.contains('unsplash.com') || currentCover.isEmpty || _gallery.isEmpty) {
        await Supabase.instance.client.from('public_treks').update({'image_url': publicUrl}).eq('id', widget.trek['id']);
        setState(() => widget.trek['image_url'] = publicUrl);
      }

      await _fetchSocialData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo added to gallery!'), backgroundColor: Colors.green));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoadingSocial = false);
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> imageObj) async {
    setState(() => _isLoadingSocial = true);
    try {
      await Supabase.instance.client.from('trek_gallery').delete().eq('id', imageObj['id']);
      try {
        final cleanUrl = imageObj['image_url'].toString().split('?').first;
        final fileName = cleanUrl.split('/').last;
        await Supabase.instance.client.storage.from('TrailImages').remove([fileName]);
      } catch (_) {} 

      await _fetchSocialData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo removed.'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent));
      setState(() => _isLoadingSocial = false);
    }
  }

  void _showImageOptions(Map<String, dynamic> imageObj) {
    final imageUrl = imageObj['image_url'];
    final isUploader = imageObj['user_id'] == Supabase.instance.client.auth.currentUser?.id;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardSurface,
        contentPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenImageViewer(imageUrl: imageUrl)));
              },
              child: SizedBox(
                height: 250,
                width: MediaQuery.of(context).size.width, // Fixes infinite width error
                child: Image.network(imageUrl, fit: BoxFit.cover),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.fullscreen, color: Colors.white),
              title: const Text('View Full Screen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenImageViewer(imageUrl: imageUrl)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.wallpaper, color: neonAccent),
              title: const Text('Set as Trail Cover Photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await Supabase.instance.client.from('public_treks').update({'image_url': imageUrl}).eq('id', widget.trek['id']);
                  setState(() => widget.trek['image_url'] = imageUrl);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cover photo updated!'), backgroundColor: Colors.green));
                } catch(e) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update cover.'), backgroundColor: Colors.redAccent));
                }
              },
            ),
            if (isUploader)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Photo', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deletePhoto(imageObj);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.grey),
              title: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onTap: () => Navigator.pop(ctx),
            )
          ],
        ),
      )
    );
  }

  Future<void> _exportGPX() async {
    try {
      await GPXHelper.exportAndShareTrek(widget.trek);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export GPX: $e'), backgroundColor: Colors.redAccent));
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
    } catch(_) {}
  }

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    try {
      List<LatLng> pts = [];
      final routeData = widget.trek['route_geojson'] ?? widget.trek['route_geom'];
      
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

      if (pts.isNotEmpty && _mapController != null) {
        await _mapController!.addLine(LineOptions(
          geometry: pts, 
          lineColor: '#D4FF00', 
          lineWidth: 5.0, 
          lineJoin: 'round'
        ));
        
        await _mapController!.addCircle(CircleOptions(geometry: pts.first, circleRadius: 6.0, circleColor: '#00C853', circleStrokeWidth: 2.0, circleStrokeColor: '#FFFFFF'));
        await _mapController!.addCircle(CircleOptions(geometry: pts.last, circleRadius: 6.0, circleColor: '#FC4C02', circleStrokeWidth: 2.0, circleStrokeColor: '#FFFFFF'));

        double minLat = pts.first.latitude, maxLat = pts.first.latitude;
        double minLng = pts.first.longitude, maxLng = pts.first.longitude;
        for (var p in pts) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }

        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 
          top: 40, bottom: 40, left: 40, right: 40
        ));
      }
    } catch (e) {
      debugPrint('❌ Error drawing route on style loaded: $e');
    }
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

  @override
  Widget build(BuildContext context) {
    final heroImageUrl = widget.trek['image_url'] ?? 'https://images.unsplash.com/photo-1454496522488-7a8e488e8606?q=80&w=1000&auto=format&fit=crop';
    final trailName = widget.trek['name'] ?? 'Unknown Trail';
    final difficulty = widget.trek['difficulty'] ?? 'Moderate';
    
    final distKm = widget.trek['distance_meters'] != null ? ((widget.trek['distance_meters'] as num) / 1000).toStringAsFixed(1) : '0.0';
    final elevation = widget.trek['elevation_gain'] != null ? '${(widget.trek['elevation_gain'] as num).toStringAsFixed(0)} m' : '0 m';

    final creatorName = widget.trek['creator_name'] ?? 'Athlete';
    final creatorAvatar = widget.trek['creator_avatar'] ?? 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?q=80&w=200&auto=format&fit=crop';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // COLLAPSING HERO IMAGE
          SliverAppBar(
            expandedHeight: 280.0,
            pinned: true,
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.arrow_back, color: Colors.white, size: 20)),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.ios_share, color: Colors.white, size: 20)),
                onPressed: _exportGPX,
              ),
              IconButton(
                icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: Icon(_hasLiked ? Icons.favorite : Icons.favorite_border, color: _hasLiked ? Colors.redAccent : Colors.white, size: 20)),
                onPressed: _toggleLike,
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              // Wrap the ENTIRE stack in a detector to prevent 0-size hit testing!
              background: GestureDetector(
                onTap: () {
                  if (heroImageUrl.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenImageViewer(imageUrl: heroImageUrl)));
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(heroImageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: cardSurface, child: const Icon(Icons.terrain, size: 64, color: Colors.white24))),
                    DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, bgColor], stops: const [0.5, 1.0]))),
                  ],
                ),
              ),
            ),
          ),

          // CONTENT
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(trailName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.2))),
                      Container(margin: const EdgeInsets.only(left: 16, top: 4), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: difficulty.toUpperCase() == 'HARD' ? Colors.redAccent.withValues(alpha: 0.2) : neonAccent.withValues(alpha: 0.2), border: Border.all(color: difficulty.toUpperCase() == 'HARD' ? Colors.redAccent : neonAccent), borderRadius: BorderRadius.circular(12)), child: Text(difficulty.toUpperCase(), style: TextStyle(color: difficulty.toUpperCase() == 'HARD' ? Colors.redAccent : neonAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // CREATOR CARD
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 18, backgroundColor: Colors.grey[800], backgroundImage: NetworkImage(creatorAvatar), onBackgroundImageError: (e, s) => {}),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [const Text('Mapped by ', style: TextStyle(color: Colors.grey, fontSize: 11)), Text(creatorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // STATS ROW
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetricColumn('Distance', '$distKm km'),
                      _buildMetricColumn('Elevation Gain', elevation),
                      _buildMetricColumn('Est. Time', _calculateEstimatedTime()),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // MINI MAP PREVIEW
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Route Overview', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => FullscreenRouteMapScreen(trek: widget.trek)));
                        },
                        icon: const Icon(Icons.fullscreen, color: neonAccent, size: 18),
                        label: const Text('Expand', style: TextStyle(color: neonAccent, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => FullscreenRouteMapScreen(trek: widget.trek)));
                    },
                    child: SizedBox(
                      height: 180, 
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AbsorbPointer(
                          child: (widget.trek['route_geojson'] != null || widget.trek['route_geom'] != null)
                              ? MapLibreMap(
                                  onMapCreated: _onMapCreated, 
                                  onStyleLoadedCallback: _onStyleLoaded,
                                  styleString: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json', 
                                  initialCameraPosition: CameraPosition(
                                    target: LatLng(
                                      widget.trek['start_lat'] ?? 0.0, 
                                      widget.trek['start_lng'] ?? 0.0
                                    ), 
                                    zoom: 13.0
                                  ), 
                                  myLocationEnabled: false, 
                                  compassEnabled: false, 
                                  scrollGesturesEnabled: false, 
                                  zoomGesturesEnabled: false,
                                  rotateGesturesEnabled: false,
                                  tiltGesturesEnabled: false,
                                )
                              : Container(
                                  color: cardSurface,
                                  alignment: Alignment.center,
                                  child: const Text('Route geometry not available', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ),
                        ),
                      )
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ELEVATION SCRUBBER
                  const Row(children: [Icon(Icons.show_chart, color: neonAccent, size: 20), SizedBox(width: 8), Text('Elevation Profile', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 16),
                  const InteractiveElevationScrubber(),
                  const SizedBox(height: 32),

                  // TRAIL GALLERY SECTION
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(children: [Icon(Icons.photo_library, color: neonAccent, size: 20), SizedBox(width: 8), Text('Trail Gallery', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                      if (widget.trek['id'] != 'imported_gpx')
                        TextButton.icon(
                          onPressed: _uploadGalleryPhoto, 
                          icon: const Icon(Icons.add_a_photo, color: neonAccent, size: 16), 
                          label: const Text('Add Photo', style: TextStyle(color: neonAccent))
                        ),
                    ]
                  ),
                  const SizedBox(height: 12),
                  if (widget.trek['id'] != 'imported_gpx')
                    _isLoadingSocial 
                      ? const Center(child: CircularProgressIndicator(color: neonAccent))
                      : _gallery.isEmpty
                          ? Container(
                              width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                              child: const Text('No photos yet. Be the first to add one!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                            )
                          : SizedBox(
                              height: 140,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _gallery.length,
                                itemBuilder: (ctx, i) {
                                  return GestureDetector(
                                    onTap: () => _showImageOptions(_gallery[i]),
                                    child: Container(
                                      width: 140, margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), image: DecorationImage(image: NetworkImage(_gallery[i]['image_url']), fit: BoxFit.cover)),
                                    )
                                  );
                                }
                              )
                            ),
                  const SizedBox(height: 32),

                  // SOCIAL LOGIC
                  if (widget.trek['id'] != 'imported_gpx') ...[
                    Row(children: [const Icon(Icons.chat_bubble_outline, color: neonAccent, size: 20), const SizedBox(width: 8), Text('${_comments.length} Reviews & Conditions', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                    const SizedBox(height: 16),
                    _isLoadingSocial 
                      ? const Center(child: CircularProgressIndicator(color: neonAccent))
                      : _comments.isEmpty 
                        ? const Text("No conditions reported yet. Be the first to review!", style: TextStyle(color: Colors.grey, fontSize: 13))
                        : ListView.builder(
                            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero, itemCount: _comments.length,
                            itemBuilder: (ctx, i) {
                              final c = _comments[i];
                              return Padding(padding: const EdgeInsets.only(bottom: 12.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [CircleAvatar(radius: 16, backgroundImage: c['avatar_url'] != null ? NetworkImage(c['avatar_url']) : null, backgroundColor: const Color(0xFF007AFF)), const SizedBox(width: 12), Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c['display_name'] ?? 'Athlete', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)), const SizedBox(height: 6), Text(c['body'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.4))])))]));
                            }
                        ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _commentController, style: const TextStyle(color: Colors.white, fontSize: 14), decoration: InputDecoration(hintText: 'Add a review...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: cardSurface, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)))),
                        const SizedBox(width: 8),
                        Container(decoration: const BoxDecoration(color: neonAccent, shape: BoxShape.circle), child: IconButton(icon: const Icon(Icons.send, color: Colors.black, size: 20), onPressed: _submitComment))
                      ]
                    ),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      
      // BOTTOM ACTION BAR
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: const BoxDecoration(color: bgColor, border: Border(top: BorderSide(color: Colors.white10))),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                    icon: const Icon(Icons.navigation_rounded, size: 20),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onStartTrail();
                    },
                    label: const Text('Start Navigation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// INTERACTIVE ELEVATION SCRUBBER WIDGET
// ---------------------------------------------------------------------------
class InteractiveElevationScrubber extends StatefulWidget { const InteractiveElevationScrubber({super.key}); @override State<InteractiveElevationScrubber> createState() => _InteractiveElevationScrubberState(); }
class _InteractiveElevationScrubberState extends State<InteractiveElevationScrubber> {
  final List<double> normalizedData = [0.1, 0.15, 0.2, 0.35, 0.6, 0.8, 0.9, 1.0, 0.85, 0.6, 0.3, 0.1];
  final double minAltitude = 300.0; final double maxAltitude = 1120.0; double? scrubX;
  @override Widget build(BuildContext context) {
    return Container(
      height: 140, width: double.infinity, decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: GestureDetector(
        onPanDown: (details) => setState(() => scrubX = details.localPosition.dx), onPanUpdate: (details) => setState(() => scrubX = details.localPosition.dx), onPanEnd: (details) => setState(() => scrubX = null), onPanCancel: () => setState(() => scrubX = null),
        child: Padding(padding: const EdgeInsets.only(top: 24.0, bottom: 8.0, left: 16.0, right: 16.0), child: CustomPaint(painter: _ScrubberPainter(data: normalizedData, scrubX: scrubX, minAlt: minAltitude, maxAlt: maxAltitude))),
      ),
    );
  }
}
class _ScrubberPainter extends CustomPainter {
  final List<double> data; final double? scrubX; final double minAlt; final double maxAlt;
  _ScrubberPainter({required this.data, this.scrubX, required this.minAlt, required this.maxAlt});
  @override void paint(Canvas canvas, Size size) {
    final path = Path(); final fillPath = Path(); final stepX = size.width / (data.length - 1);
    path.moveTo(0, size.height - (data[0] * size.height)); fillPath.moveTo(0, size.height); fillPath.lineTo(0, size.height - (data[0] * size.height));
    for (int i = 1; i < data.length; i++) { final x = i * stepX; final y = size.height - (data[i] * size.height); path.lineTo(x, y); fillPath.lineTo(x, y); }
    fillPath.lineTo(size.width, size.height); fillPath.close();
    canvas.drawPath(fillPath, Paint()..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, size.height), [neonAccent.withValues(alpha: 0.3), neonAccent.withValues(alpha: 0.0)]));
    canvas.drawPath(path, Paint()..color = neonAccent..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke);
    if (scrubX != null) {
      double clampedX = scrubX!.clamp(0.0, size.width); int index = (clampedX / stepX).round().clamp(0, data.length - 1); double actualX = index * stepX; double y = size.height - (data[index] * size.height);
      canvas.drawLine(Offset(actualX, 0), Offset(actualX, size.height), Paint()..color = Colors.white38..strokeWidth = 1); canvas.drawCircle(Offset(actualX, y), 6, Paint()..color = neonAccent); canvas.drawCircle(Offset(actualX, y), 3, Paint()..color = Colors.black);
      double realAltitude = minAlt + (data[index] * (maxAlt - minAlt));
      TextPainter tp = TextPainter(text: TextSpan(text: '${realAltitude.round()} m', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)), textDirection: TextDirection.ltr); tp.layout();
      double bgWidth = tp.width + 16; double bgHeight = tp.height + 8; double tipX = actualX - (bgWidth / 2); double tipY = y - bgHeight - 12;
      if (tipX < 0) tipX = 0; if (tipX + bgWidth > size.width) tipX = size.width - bgWidth; if (tipY < 0) tipY = y + 16;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tipX, tipY, bgWidth, bgHeight), const Radius.circular(8)), Paint()..color = neonAccent); tp.paint(canvas, Offset(tipX + 8, tipY + 4));
    }
  }
  @override bool shouldRepaint(covariant _ScrubberPainter oldDelegate) => oldDelegate.scrubX != scrubX;
}

// ---------------------------------------------------------------------------
// FULLSCREEN INTERACTIVE ROUTE VIEWER
// ---------------------------------------------------------------------------
class FullscreenRouteMapScreen extends StatefulWidget {
  final Map<String, dynamic> trek;
  const FullscreenRouteMapScreen({super.key, required this.trek});

  @override
  State<FullscreenRouteMapScreen> createState() => _FullscreenRouteMapScreenState();
}

class _FullscreenRouteMapScreenState extends State<FullscreenRouteMapScreen> {
  MapLibreMapController? _mapController;

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    try {
      List<LatLng> pts = [];
      final routeData = widget.trek['route_geojson'] ?? widget.trek['route_geom'];
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

      if (pts.isNotEmpty && _mapController != null) {
        await _mapController!.addLine(LineOptions(geometry: pts, lineColor: '#D4FF00', lineWidth: 6.0, lineJoin: 'round'));
        await _mapController!.addCircle(CircleOptions(geometry: pts.first, circleRadius: 7.0, circleColor: '#00C853', circleStrokeWidth: 2.0, circleStrokeColor: '#FFFFFF'));
        await _mapController!.addCircle(CircleOptions(geometry: pts.last, circleRadius: 7.0, circleColor: '#FC4C02', circleStrokeWidth: 2.0, circleStrokeColor: '#FFFFFF'));

        double minLat = pts.first.latitude, maxLat = pts.first.latitude;
        double minLng = pts.first.longitude, maxLng = pts.first.longitude;
        for (var p in pts) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }

        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 
          top: 60, bottom: 60, left: 60, right: 60
        ));
      }
    } catch (e) {
      debugPrint('Fullscreen map error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trek['name'] ?? 'Route Explorer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F1115),
        elevation: 0,
      ),
      body: MapLibreMap(
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        styleString: 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
        initialCameraPosition: CameraPosition(
          target: LatLng(widget.trek['start_lat'] ?? 0.0, widget.trek['start_lng'] ?? 0.0),
          zoom: 13.0,
        ),
        myLocationEnabled: true,
        compassEnabled: true,
        scrollGesturesEnabled: true,
        zoomGesturesEnabled: true,
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: true,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FULLSCREEN IMAGE VIEWER
// ---------------------------------------------------------------------------
class FullscreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const FullscreenImageViewer({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        iconTheme: const IconThemeData(color: Colors.white)
      ),
      extendBodyBehindAppBar: true,
      body: InteractiveViewer(
        panEnabled: true,
        minScale: 1.0,
        maxScale: 5.0,
        // Using a strictly bounded container fixes the hit-test exception!
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          alignment: Alignment.center,
          child: Image.network(
            imageUrl, 
            fit: BoxFit.contain, 
          )
        ),
      ),
    );
  }
}