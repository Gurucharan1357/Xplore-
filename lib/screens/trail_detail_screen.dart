import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart'; 
import 'package:xplore_mobile/main.dart'; 
import 'package:xplore_mobile/screens/explore_screen.dart';
import 'package:xplore_mobile/screens/my_dashboard_screen.dart'; 
import 'package:xplore_mobile/screens/navigation_screen.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

String get MAPBOX_ACCESS_TOKEN => dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
const String styleDark = 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';
String get styleStandard => '{"version": 8,"sources": {"mapbox-outdoors": {"type": "raster","tiles": ["https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$MAPBOX_ACCESS_TOKEN"],"tileSize": 256}},"layers": [{"id": "outdoors-layer","type": "raster","source": "mapbox-outdoors"}]}';
String get styleSatellite => '{"version": 8,"sources": {"mapbox-satellite": {"type": "raster","tiles": ["https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$MAPBOX_ACCESS_TOKEN"],"tileSize": 256}},"layers": [{"id": "satellite-layer","type": "raster","source": "mapbox-satellite"}]}';

// Shared function for Map Arrows
Future<Uint8List> generateIconBytes(IconData icon, Color color) async {
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

// Shared function for 3D Map Pins
Future<Uint8List> generate3DPinIcon(Color color, IconData iconData) async {
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

class TrailDetailScreen extends StatefulWidget {
  final Map<String, dynamic> trek;
  final VoidCallback onStartTrail;
  
  const TrailDetailScreen({super.key, required this.trek, required this.onStartTrail});

  @override
  State<TrailDetailScreen> createState() => _TrailDetailScreenState();
}

class _TrailDetailScreenState extends State<TrailDetailScreen> {
  MapLibreMapController? _mapController;
  bool _isSaved = false; 
  List<dynamic> _comments = [];
  List<Map<String, dynamic>> _gallery = [];
  bool _isLoadingSocial = true;
  bool _isDownloadingMap = false; 
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
      final savedRes = await Supabase.instance.client.from('saved_treks').select('user_id').eq('trek_id', trekId);
      _isSaved = savedRes.any((save) => save['user_id'] == myId);

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

  Future<void> _downloadMapRegion() async {
    if (widget.trek['id'] == 'imported_gpx') return;
    final trailName = widget.trek['name'] ?? 'Unknown Trail';
    
    final exists = OfflineMapCache.downloadedMaps.any((m) => m['name'] == trailName);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Map for "$trailName" is already downloaded!'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isDownloadingMap = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading offline map tiles for "$trailName"...'), backgroundColor: neonAccent, duration: const Duration(seconds: 2)));
    
    await Future.delayed(const Duration(seconds: 3));
    
    OfflineMapCache.downloadedMaps.add({
      'name': trailName,
      'size': '12.8 MB',
      'date': 'Downloaded Just Now'
    });
    
    if (mounted) {
      setState(() => _isDownloadingMap = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline map saved successfully! View it in your Settings > Manage Offline Maps.'), backgroundColor: Colors.green));
    }
  }

  Future<void> _shareTrail() async {
    final name = widget.trek['name'] ?? 'an awesome trail';
    final distKm = widget.trek['distance_meters'] != null ? ((widget.trek['distance_meters'] as num) / 1000).toStringAsFixed(1) : '0.0';
    final elevM = widget.trek['elevation_gain'] != null ? '${(widget.trek['elevation_gain'] as num).toStringAsFixed(0)}' : '0';
    final difficulty = widget.trek['difficulty'] ?? 'Moderate';
    final creator = widget.trek['creator_name'] ?? 'an athlete';

    final shareText = 'Check out "$name" on Xplore!\n\n📏 Distance: $distKm km\n📈 Elevation: $elevM m\n⚡ Difficulty: $difficulty\n\nMapped by $creator.';

    try {
      await Share.share(shareText, subject: 'Xplore Trail: $name');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to open share menu: $e'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _toggleSave() async {
    if (widget.trek['id'] == 'imported_gpx') return;
    final trekId = widget.trek['id'];
    final myId = Supabase.instance.client.auth.currentUser!.id;
    
    HapticFeedback.lightImpact();
    setState(() { _isSaved = !_isSaved; });
    
    try {
      if (_isSaved) {
        await Supabase.instance.client.from('saved_treks').insert({'trek_id': trekId, 'user_id': myId});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trail saved to your bookmarks!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
      } else {
        await Supabase.instance.client.from('saved_treks').delete().eq('trek_id', trekId).eq('user_id', myId);
      }
    } catch(e) {
      setState(() { _isSaved = !_isSaved; }); 
    }
  }

  // UPDATED TO SUPPORT MULTIPLE IMAGES
  Future<void> _uploadGalleryPhoto() async {
    if (widget.trek['id'] == 'imported_gpx') return;

    final picker = ImagePicker();
    // Allow users to select multiple photos at once
    final List<XFile> images = await picker.pickMultiImage(imageQuality: 80);
    if (images.isEmpty) return;

    setState(() => _isLoadingSocial = true);
    
    try {
      List<String> uploadedUrls = [];
      
      for (var image in images) {
        final file = File(image.path);
        final ext = image.path.split('.').last.toLowerCase();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${widget.trek['id']}_${images.indexOf(image)}.$ext';

        await Supabase.instance.client.storage.from('TrailImages').upload(fileName, file);
        final publicUrl = Supabase.instance.client.storage.from('TrailImages').getPublicUrl(fileName);

        await Supabase.instance.client.from('trek_gallery').insert({
          'trek_id': widget.trek['id'],
          'user_id': Supabase.instance.client.auth.currentUser!.id,
          'image_url': publicUrl
        });
        
        uploadedUrls.add(publicUrl);
      }

      // Update the main cover photo if it's currently empty
      final currentCover = widget.trek['image_url'] ?? '';
      if (currentCover.contains('unsplash.com') || currentCover.isEmpty || _gallery.isEmpty) {
        // Pointing to completed_treks!
        await Supabase.instance.client.from('completed_treks').update({'image_url': uploadedUrls.first}).eq('id', widget.trek['id']);
        setState(() => widget.trek['image_url'] = uploadedUrls.first);
      }

      await _fetchSocialData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(images.length == 1 ? 'Photo added to gallery!' : '${images.length} photos added!'), 
          backgroundColor: Colors.green
        ));
      }
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
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    
    final isPhotoUploader = imageObj['user_id'] == currentUserId;
    final isTrailOwner = widget.trek['creator_id'] == currentUserId;

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
                width: MediaQuery.of(context).size.width,
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
            
            if (isTrailOwner)
              ListTile(
                leading: const Icon(Icons.wallpaper, color: neonAccent),
                title: const Text('Set as Trail Cover Photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    // Pointing to completed_treks!
                    await Supabase.instance.client.from('completed_treks').update({'image_url': imageUrl}).eq('id', widget.trek['id']);
                    setState(() => widget.trek['image_url'] = imageUrl);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cover photo updated!'), backgroundColor: Colors.green));
                  } catch(e) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update cover.'), backgroundColor: Colors.redAccent));
                  }
                },
              ),
              
            if (isPhotoUploader)
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

  void _showEditTrailSheet() {
    final nameCtrl = TextEditingController(text: widget.trek['name'] ?? '');
    List<dynamic> currentTags = widget.trek['tags'] ?? [];
    final tagsCtrl = TextEditingController(text: currentTags.join(', '));
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit Trail Details', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 20),
              
              const Text('Keywords & Hashtags (comma separated)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: tagsCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. Mysore, Sunset, Muddy',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true, fillColor: bgColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 32),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: isSaving ? null : () async {
                    setSheetState(() => isSaving = true);
                    try {
                      final rawTags = tagsCtrl.text.split(',');
                      List<String> formattedTags = [];
                      for (var t in rawTags) {
                        String clean = t.trim().toLowerCase().replaceAll('#', '');
                        if (clean.isNotEmpty) {
                          formattedTags.add(clean);
                        }
                      }

                      // Pointing to completed_treks!
                      await Supabase.instance.client.from('completed_treks').update({
                        'trek_name': nameCtrl.text.trim(),
                        'tags': formattedTags,
                      }).eq('id', widget.trek['id']);

                      setState(() {
                        widget.trek['name'] = nameCtrl.text.trim();
                        widget.trek['tags'] = formattedTags;
                      });
                      
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trail updated successfully!'), backgroundColor: Colors.green));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.redAccent));
                    } finally {
                      setSheetState(() => isSaving = false);
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        )
      )
    );
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
      
      if (routeData != null) {
        if (routeData is String && routeData.contains('LINESTRING')) {
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
          dynamic parsed = routeData;
          if (routeData is String) {
            try { parsed = jsonDecode(routeData); } catch (_) {}
          }
          
          if (parsed is List) {
            for (var p in parsed) {
              if (p is Map) {
                final lat = (p['lat'] as num?)?.toDouble();
                final lng = (p['lng'] as num?)?.toDouble();
                if (lat != null && lng != null) pts.add(LatLng(lat, lng));
              } else if (p is List && p.length >= 2) {
                pts.add(LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()));
              }
            }
          } else if (parsed is Map) {
            final coordinates = parsed['coordinates'] ?? parsed['geometry']?['coordinates'] ?? [];
            for (var c in coordinates) {
              if (c is List && c.length >= 2) pts.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
            }
          }
        }
      }

      if (pts.isNotEmpty && _mapController != null) {
        List<List<double>> coords = pts.map((p) => [p.longitude, p.latitude]).toList();
        final routeGeoJson = {
          "type": "FeatureCollection",
          "features": [{"type": "Feature", "properties": {}, "geometry": {"type": "LineString", "coordinates": coords}}]
        };

        try {
          await _mapController!.addSource("route-source", GeojsonSourceProperties(data: routeGeoJson));
          
          await _mapController!.addLineLayer("route-source", "route-casing", const LineLayerProperties(lineColor: "#FFFFFF", lineWidth: 10.0, lineCap: "round", lineJoin: "round"));
          await _mapController!.addLineLayer("route-source", "route-layer", const LineLayerProperties(lineColor: "#D4FF00", lineWidth: 6.0, lineCap: "round", lineJoin: "round"));

          try {
            final Uint8List arrowBytes = await generateIconBytes(Icons.keyboard_double_arrow_right_rounded, Colors.white70);
            await _mapController!.addImage("route-arrow", arrowBytes);
            await _mapController!.addSymbolLayer("route-source", "route-arrows", const SymbolLayerProperties(
              symbolPlacement: "line", symbolSpacing: 75.0, iconImage: "route-arrow", iconSize: 0.35, iconAllowOverlap: true,
            ));
          } catch (_) {}

          final start = pts.first;
          final end = pts.last;

          try {
            final Uint8List start3DPin = await generate3DPinIcon(const Color(0xFF0088FF), Icons.play_arrow_rounded);
            await _mapController!.addImage("start-3d-pin", start3DPin);
            
            final Uint8List end3DPin = await generate3DPinIcon(const Color(0xFFFF0044), Icons.flag_rounded);
            await _mapController!.addImage("end-3d-pin", end3DPin);
          } catch (_) {}

          await _mapController!.addSource("start-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [start.longitude, start.latitude]}}]}));
          await _mapController!.addSymbolLayer("start-source", "start-layer", const SymbolLayerProperties(
            iconImage: "start-3d-pin", iconSize: 0.5, iconAnchor: "bottom", iconAllowOverlap: true
          ));

          await _mapController!.addSource("end-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [end.longitude, end.latitude]}}]}));
          await _mapController!.addSymbolLayer("end-source", "end-layer", const SymbolLayerProperties(
            iconImage: "end-3d-pin", iconSize: 0.5, iconAnchor: "bottom", iconAllowOverlap: true
          ));
        } catch(e) {
            debugPrint("Layer error: $e");
        }

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
    
    final isTrailOwner = widget.trek['creator_id'] == Supabase.instance.client.auth.currentUser?.id;
    final List<dynamic> currentTags = widget.trek['tags'] ?? [];
    
    final distKm = widget.trek['distance_meters'] != null ? ((widget.trek['distance_meters'] as num) / 1000).toStringAsFixed(1) : '0.0';
    final elevation = widget.trek['elevation_gain'] != null ? '${(widget.trek['elevation_gain'] as num).toStringAsFixed(0)} m' : '0 m';

    final creatorName = widget.trek['creator_name'] ?? 'Athlete';
    final creatorAvatar = widget.trek['creator_avatar'] ?? 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?q=80&w=200&auto=format&fit=crop';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
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
              if (isTrailOwner)
                IconButton(
                  icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.edit, color: Colors.white, size: 20)),
                  onPressed: _showEditTrailSheet,
                ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8), 
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), 
                  child: _isDownloadingMap 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: neonAccent, strokeWidth: 2)) 
                      : const Icon(Icons.download_for_offline, color: Colors.white, size: 20)
                ),
                onPressed: _isDownloadingMap ? null : _downloadMapRegion,
              ),
              IconButton(
                icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.ios_share, color: Colors.white, size: 20)),
                onPressed: _shareTrail,
              ),
              IconButton(
                icon: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_border, color: _isSaved ? neonAccent : Colors.white, size: 20)),
                onPressed: _toggleSave,
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
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
                  if (currentTags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: currentTags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: cardSurface, border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                          child: Text('#$tag', style: const TextStyle(color: neonAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        )).toList(),
                      ),
                    ),
                  const SizedBox(height: 16),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetricColumn('Distance', '$distKm km'),
                      _buildMetricColumn('Elevation Gain', elevation),
                      _buildMetricColumn('Est. Time', _calculateEstimatedTime()),
                    ],
                  ),
                  const SizedBox(height: 28),
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
                                  styleString: styleDark, 
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
                  const Row(children: [Icon(Icons.show_chart, color: neonAccent, size: 20), SizedBox(width: 8), Text('Elevation Profile', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 16),
                  const InteractiveElevationScrubber(),
                  const SizedBox(height: 32),
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 24),
        decoration: const BoxDecoration(color: bgColor, border: Border(top: BorderSide(color: Colors.white10))),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 14),
                  SizedBox(width: 6),
                  Text('You can follow this route in reverse during navigation.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: neonAccent, 
                          foregroundColor: Colors.black, 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                          elevation: 0
                        ),
                        icon: const Icon(Icons.navigation_rounded, size: 20),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NavigationScreen(trekToFollow: widget.trek),
                            ),
                          );
                        },
                        label: const Text('Start Navigation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
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

class FullscreenRouteMapScreen extends StatefulWidget {
  final Map<String, dynamic> trek;
  const FullscreenRouteMapScreen({super.key, required this.trek});

  @override
  State<FullscreenRouteMapScreen> createState() => _FullscreenRouteMapScreenState();
}

class _FullscreenRouteMapScreenState extends State<FullscreenRouteMapScreen> {
  MapLibreMapController? _mapController;
  String _currentMapStyle = styleDark; 

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    try {
      List<LatLng> pts = [];
      final routeData = widget.trek['route_geojson'] ?? widget.trek['route_geom'];
      if (routeData == null) return;

      if (routeData != null) {
        if (routeData is String && routeData.contains('LINESTRING')) {
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
          dynamic parsed = routeData;
          if (routeData is String) {
            try { parsed = jsonDecode(routeData); } catch (_) {}
          }
          
          if (parsed is List) {
            for (var p in parsed) {
              if (p is Map) {
                final lat = (p['lat'] as num?)?.toDouble();
                final lng = (p['lng'] as num?)?.toDouble();
                if (lat != null && lng != null) pts.add(LatLng(lat, lng));
              } else if (p is List && p.length >= 2) {
                pts.add(LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()));
              }
            }
          } else if (parsed is Map) {
            final coordinates = parsed['coordinates'] ?? parsed['geometry']?['coordinates'] ?? [];
            for (var c in coordinates) {
              if (c is List && c.length >= 2) pts.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
            }
          }
        }
      }

      if (pts.isNotEmpty && _mapController != null) {
        List<List<double>> coords = pts.map((p) => [p.longitude, p.latitude]).toList();
        final routeGeoJson = {
          "type": "FeatureCollection",
          "features": [{"type": "Feature", "properties": {}, "geometry": {"type": "LineString", "coordinates": coords}}]
        };

        try {
          await _mapController!.addSource("route-source", GeojsonSourceProperties(data: routeGeoJson));
          
          await _mapController!.addLineLayer("route-source", "route-casing", const LineLayerProperties(lineColor: "#FFFFFF", lineWidth: 12.0, lineCap: "round", lineJoin: "round"));
          await _mapController!.addLineLayer("route-source", "route-layer", const LineLayerProperties(lineColor: "#D4FF00", lineWidth: 6.0, lineCap: "round", lineJoin: "round"));

          try {
            final Uint8List arrowBytes = await generateIconBytes(Icons.keyboard_double_arrow_right_rounded, Colors.white70);
            await _mapController!.addImage("route-arrow", arrowBytes);
            await _mapController!.addSymbolLayer("route-source", "route-arrows", const SymbolLayerProperties(
              symbolPlacement: "line", symbolSpacing: 75.0, iconImage: "route-arrow", iconSize: 0.4, iconAllowOverlap: true,
            ));
          } catch (_) {}

          final start = pts.first;
          final end = pts.last;

          try {
            final Uint8List start3DPin = await generate3DPinIcon(const Color(0xFF0088FF), Icons.play_arrow_rounded);
            await _mapController!.addImage("start-3d-pin", start3DPin);
            
            final Uint8List end3DPin = await generate3DPinIcon(const Color(0xFFFF0044), Icons.flag_rounded);
            await _mapController!.addImage("end-3d-pin", end3DPin);
          } catch (_) {}

          await _mapController!.addSource("start-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [start.longitude, start.latitude]}}]}));
          await _mapController!.addSymbolLayer("start-source", "start-layer", const SymbolLayerProperties(
            iconImage: "start-3d-pin", iconSize: 0.5, iconAnchor: "bottom", iconAllowOverlap: true
          ));

          await _mapController!.addSource("end-source", GeojsonSourceProperties(data: {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [end.longitude, end.latitude]}}]}));
          await _mapController!.addSymbolLayer("end-source", "end-layer", const SymbolLayerProperties(
            iconImage: "end-3d-pin", iconSize: 0.5, iconAnchor: "bottom", iconAllowOverlap: true
          ));
        } catch(e) {
            debugPrint("Layer error: $e");
        }

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
            decoration: BoxDecoration(color: isSelected ? neonAccent.withValues(alpha: 0.2) : bgColor, shape: BoxShape.circle, border: Border.all(color: isSelected ? neonAccent : Colors.white10, width: 2)),
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
      appBar: AppBar(
        title: Text(widget.trek['name'] ?? 'Route Explorer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F1115),
        elevation: 0,
      ),
      body: Stack(
        children: [
          MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            styleString: _currentMapStyle, 
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
          Positioned(
            right: 16,
            bottom: 32,
            child: FloatingActionButton(
              heroTag: 'overview_layers_btn',
              backgroundColor: cardSurface,
              onPressed: _showMapStyleSelector,
              child: const Icon(Icons.layers, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

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