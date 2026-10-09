import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xplore_mobile/main.dart'; 
import 'package:xplore_mobile/screens/trail_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';

// Import the new offline sync manager
import 'package:xplore_mobile/utils/offline_sync_manager.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class MyDashboardScreen extends StatefulWidget {
  final Function(Map<String, dynamic>)? onSelectTrek;
  
  const MyDashboardScreen({super.key, this.onSelectTrek});

  @override
  State<MyDashboardScreen> createState() => _MyDashboardScreenState();
}

class _MyDashboardScreenState extends State<MyDashboardScreen> {
  bool _isLoading = true;
  bool _isSyncing = false;
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _myTreks = []; 
  int _followersCount = 0;
  int _followingCount = 0;
  
  // Track offline sync count
  int _pendingSyncCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    _checkCrashRecovery(); // Fire crash recovery check on boot
  }

  Future<void> _checkCrashRecovery() async {
    final hasUnfinished = await OfflineSyncManager.hasUnfinishedTrek();
    if (hasUnfinished && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: cardSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Unfinished Trek Detected', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('It looks like your app closed while you were recording a trail. What would you like to do?', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () async {
                await OfflineSyncManager.clearUnfinishedTrek();
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Discard', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                Navigator.pop(ctx);
                if (widget.onSelectTrek != null) {
                  // Pass an empty map to act as a flag to resume tracking in the HUD
                  widget.onSelectTrek!({'resume_crash_recovery': true});
                }
              },
              child: const Text('Resume Tracking', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        )
      );
    }
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (currentUserId == null) return;

    try {
      final profileResponse = await Supabase.instance.client.from('profiles').select().eq('id', currentUserId).maybeSingle();
      final followers = await Supabase.instance.client.from('follows').select('follower_id').eq('following_id', currentUserId);
      final following = await Supabase.instance.client.from('follows').select('following_id').eq('follower_id', currentUserId);
      final List<dynamic> trekData = await Supabase.instance.client.from('public_treks').select().eq('creator_id', currentUserId).order('created_at', ascending: false);
      
      // Check offline cache for pending uploads
      final pendingTreks = await OfflineSyncManager.getPendingTreks();
          
      if (mounted) {
        setState(() {
          _userProfile = profileResponse;
          _followersCount = followers.length;
          _followingCount = following.length;
          _pendingSyncCount = pendingTreks.length;

          final myName = profileResponse?['display_name'] ?? 'Athlete';
          final myAvatar = profileResponse?['avatar_url'];

          _myTreks = trekData.map<Map<String, dynamic>>((t) => {
            ...t, 
            'isHidden': false,
            'creator_name': myName,
            'creator_avatar': myAvatar,
          }).toList();

          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _pickAndUploadAvatar() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );

      if (image == null) return; 

      setState(() => _isLoading = true);

      final userId = Supabase.instance.client.auth.currentUser!.id;
      final fileExtension = image.path.split('.').last.toLowerCase();
      final fileName = 'avatar_$userId.${fileExtension == 'jpg' ? 'jpeg' : fileExtension}';
      
      final File file = File(image.path);

      await Supabase.instance.client.storage
          .from('Avatars')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      final String publicUrl = Supabase.instance.client.storage.from('Avatars').getPublicUrl(fileName);
      final String bustedUrl = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      
      await Supabase.instance.client.from('profiles').update({'avatar_url': bustedUrl}).eq('id', userId);

      _fetchDashboardData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!'), backgroundColor: Colors.green));
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update avatar: $e'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    final syncedCount = await OfflineSyncManager.syncPending(); // Wired to the manager method
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(syncedCount > 0 ? 'Successfully synced $syncedCount treks!' : 'Network still unavailable.'), backgroundColor: syncedCount > 0 ? Colors.green : Colors.orange));
      setState(() => _isSyncing = false);
      _fetchDashboardData(); // Refresh UI to clear the banner if successful
    }
  }

  void _hideTrail(String id) {
    setState(() {
      final index = _myTreks.indexWhere((t) => t['id'] == id);
      if (index != -1) _myTreks[index]['isHidden'] = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trail hidden from your profile.')));
  }

  void _restoreHiddenTrails() {
    setState(() {
      for (var trek in _myTreks) { trek['isHidden'] = false; }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All hidden trails restored!')));
  }

  void _showProfileImagePopup(String avatarUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Center(
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            panEnabled: true, minScale: 1.0, maxScale: 4.0,
            child: Hero(
              tag: 'avatar_hero', 
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24), 
                child: Image.network(
                  avatarUrl, width: MediaQuery.of(context).size.width * 0.85, height: MediaQuery.of(context).size.width * 0.85, fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(width: MediaQuery.of(context).size.width * 0.85, height: MediaQuery.of(context).size.width * 0.85, color: cardSurface, child: const Icon(Icons.person, size: 100, color: Colors.grey)),
                )
              )
            ),
          ),
        ),
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _userProfile?['display_name'] ?? '');
    final userCtrl = TextEditingController(text: _userProfile?['username'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Display Name', labelStyle: TextStyle(color: Colors.grey), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: neonAccent)))),
            const SizedBox(height: 16),
            TextField(controller: userCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Username', prefixText: '@ ', labelStyle: TextStyle(color: Colors.grey), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: neonAccent)))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
            onPressed: () async { 
              try { 
                await Supabase.instance.client.from('profiles').update({'display_name': nameCtrl.text.trim(), 'username': userCtrl.text.trim()}).eq('id', Supabase.instance.client.auth.currentUser!.id); 
                Navigator.pop(ctx); 
                _fetchDashboardData(); 
              } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e'))); } 
            }, 
            child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context, backgroundColor: cardSurface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            ListTile(leading: const Icon(Icons.settings, color: Colors.white), title: const Text('App Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSettingsScreen())); }),
            ListTile(leading: const Icon(Icons.download_for_offline, color: Colors.white), title: const Text('Manage Offline Maps', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageOfflineMapsScreen())); }),
            ListTile(leading: const Icon(Icons.help_outline, color: Colors.white), title: const Text('Help & Support', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen())); }),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: Colors.white10)),
            ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: () async { Navigator.pop(ctx); await Supabase.instance.client.auth.signOut(); }),
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: bgColor, body: Center(child: CircularProgressIndicator(color: neonAccent)));
    }

    final displayName = _userProfile?['display_name'] ?? 'Athlete';
    final username = '@${_userProfile?['username'] ?? 'explorer'}';
    final avatarUrl = _userProfile?['avatar_url'] ?? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=500&auto=format&fit=crop';

    final totalDistanceKm = _myTreks.fold<double>(0.0, (acc, item) => acc + ((item['distance_meters'] ?? 0) as num)) / 1000;
    final totalElevationM = _myTreks.fold<double>(0.0, (acc, item) => acc + ((item['elevation_gain'] ?? 0) as num));
    
    final visibleTreks = _myTreks.where((t) => t['isHidden'] == false).toList();
    final hasHiddenTreks = _myTreks.any((t) => t['isHidden'] == true);

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: neonAccent, backgroundColor: cardSurface,
        onRefresh: _fetchDashboardData,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _showProfileImagePopup(avatarUrl),
                            child: Hero(
                              tag: 'avatar_hero', 
                              child: Container(
                                padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: neonAccent, width: 2)), 
                                child: CircleAvatar(radius: 34, backgroundColor: Colors.grey[800], backgroundImage: NetworkImage(avatarUrl), onBackgroundImageError: (e, s) => {})
                              )
                            ),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: GestureDetector(
                              onTap: _pickAndUploadAvatar,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: neonAccent, shape: BoxShape.circle, border: Border.all(color: bgColor, width: 2)),
                                child: const Icon(Icons.camera_alt, color: Colors.black, size: 14),
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('My Dashboard', style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          Row(children: [Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(width: 8), GestureDetector(onTap: _showEditProfileDialog, child: const Icon(Icons.edit_square, color: neonAccent, size: 16))]),
                          Text(username, style: TextStyle(color: neonAccent.withValues(alpha: 0.7), fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  GestureDetector(onTap: _showSettingsMenu, child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: cardSurface, shape: BoxShape.circle), child: const Icon(Icons.menu, color: Colors.white, size: 22)))
                ],
              ),
              
              // Dynamic Batch Sync Banner
              if (_pendingSyncCount > 0)
                Container(
                  margin: const EdgeInsets.only(top: 24, bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange.withValues(alpha: 0.5))),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.orange), 
                      const SizedBox(width: 12), 
                      Expanded(child: Text('$_pendingSyncCount treks waiting to sync.', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))), 
                      _isSyncing 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2)) 
                        : TextButton(onPressed: _triggerSync, child: const Text('Sync', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)))
                    ]
                  ),
                )
              else 
                const SizedBox(height: 32),

              const Text("Lifetime Stats", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildHeroStat('Total Dist', totalDistanceKm.toStringAsFixed(1), 'km'),
                        _buildHeroStat('Total Elev', totalElevationM.toStringAsFixed(0), 'm'),
                        _buildHeroStat('Treks', '${_myTreks.length}', ''),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Row(children: [Icon(Icons.show_chart, color: neonAccent, size: 16), SizedBox(width: 6), Text('Recent Elevation Progress', style: TextStyle(color: Colors.grey, fontSize: 12))]),
                    const SizedBox(height: 12),
                    SizedBox(height: 60, width: double.infinity, child: CustomPaint(painter: _NeonSparklinePainter(neonAccent))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(child: _buildCommunityPill('$_followersCount', 'Followers')),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCommunityPill('$_followingCount', 'Following')),
                ],
              ),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("My Recorded Trails", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (hasHiddenTreks) TextButton(onPressed: _restoreHiddenTrails, child: const Text("Show Hidden", style: TextStyle(color: neonAccent, fontSize: 13, fontWeight: FontWeight.bold)))
                ],
              ),
              const SizedBox(height: 12),
              
              visibleTreks.isEmpty 
                ? _buildEmptyTrailsState() 
                : SizedBox(
                    height: 260,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: visibleTreks.length,
                      itemBuilder: (context, index) {
                        return _buildMyTrailCard(visibleTreks[index]);
                      },
                    ),
                  )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStat(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), if (unit.isNotEmpty) Text(' $unit', style: const TextStyle(color: Colors.grey, fontSize: 12))],
        )
      ],
    );
  }

  Widget _buildCommunityPill(String number, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [Text(number, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))]),
    );
  }

  Widget _buildEmptyTrailsState() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10, width: 1.5)),
      child: Column(
        children: [
          Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: cardSurface, shape: BoxShape.circle), child: const Icon(Icons.landscape, size: 48, color: Colors.grey)),
          const SizedBox(height: 24),
          const Text("No trails recorded yet", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text("Hit the trail and record your first adventure.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildMyTrailCard(Map<String, dynamic> trek) {
    final distKm = ((trek['distance_meters'] ?? 0) / 1000).toStringAsFixed(1);
    final elevM = (trek['elevation_gain'] ?? 0).toStringAsFixed(0);
    final dateRaw = DateTime.parse(trek['created_at'] ?? DateTime.now().toIso8601String());
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[dateRaw.month - 1]} ${dateRaw.day}, ${dateRaw.year}';
    final imageUrl = trek['image_url'] ?? 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?q=80&w=600&auto=format&fit=crop';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(
          trek: trek, 
          onStartTrail: () {
            if (widget.onSelectTrek != null) {
              widget.onSelectTrek!(trek);
            }
          }
        )));
      },
      child: Container(
        width: 260, margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ShaderMask(
                shaderCallback: (rect) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)], stops: const [0.3, 1.0]).createShader(rect),
                blendMode: BlendMode.darken,
                child: Image.network(imageUrl, height: double.infinity, width: double.infinity, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: bgColor, child: const Icon(Icons.terrain, color: Colors.white24, size: 48))),
              ),
            ),
            Positioned(
              top: 12, left: 12, right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)), child: Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                  Container(
                    padding: EdgeInsets.zero, decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white, size: 18), color: cardSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (value) async {
                        if (value == 'Hide') {
                          _hideTrail(trek['id']);
                        } else if (value == 'Delete') {
                          await Supabase.instance.client.from('public_treks').delete().eq('id', trek['id']);
                          _fetchDashboardData();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edit details coming soon!')));
                        }
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(value: 'Edit', child: Text('Edit Details', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem<String>(value: 'Hide', child: Text('Hide from Profile', style: TextStyle(color: Colors.white))),
                        const PopupMenuDivider(height: 1),
                        const PopupMenuItem<String>(value: 'Delete', child: Text('Delete Trek', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  )
                ],
              ),
            ),
            Positioned(
              bottom: 16, left: 16, right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trek['name'] ?? 'Wilderness Trek', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.straighten, color: neonAccent, size: 14), const SizedBox(width: 4), Text('$distKm km', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(width: 12),
                      const Icon(Icons.trending_up, color: neonAccent, size: 14), const SizedBox(width: 4), Text('${elevM}m', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _NeonSparklinePainter extends CustomPainter {
  final Color color; _NeonSparklinePainter(this.color);
  @override void paint(Canvas canvas, Size size) {
    final List<double> data = [0.2, 0.4, 0.3, 0.6, 0.5, 0.8, 0.7, 0.9, 0.8, 1.0];
    final path = Path(); final fillPath = Path(); final stepX = size.width / (data.length - 1);
    path.moveTo(0, size.height - (data[0] * size.height)); fillPath.moveTo(0, size.height); fillPath.lineTo(0, size.height - (data[0] * size.height));
    for (int i = 1; i < data.length; i++) { final x = i * stepX; final y = size.height - (data[i] * size.height); path.lineTo(x, y); fillPath.lineTo(x, y); }
    fillPath.lineTo(size.width, size.height); fillPath.close();
    canvas.drawPath(fillPath, Paint()..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, size.height), [color.withValues(alpha: 0.4), color.withValues(alpha: 0.0)]));
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 3.0..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// APP SETTINGS PERSISTENCE MANAGER
// ---------------------------------------------------------------------------
class AppSettings {
  static final ValueNotifier<bool> amoledMode = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> autoPause = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> metricUnits = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> backgroundTracking = ValueNotifier<bool>(true);
}

// ---------------------------------------------------------------------------
// 1. SETTINGS SCREEN
// ---------------------------------------------------------------------------
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});
  @override State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('App Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: bgColor, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSectionHeader('Map & Navigation'),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.amoledMode,
            builder: (context, value, _) => SwitchListTile(
              activeThumbColor: neonAccent, activeTrackColor: neonAccent.withValues(alpha: 0.3),
              title: const Text('AMOLED Battery Saver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), subtitle: const Text('Forces map to pure black when tracking to save battery', style: TextStyle(color: Colors.grey, fontSize: 12)),
              value: value, onChanged: (val) { AppSettings.amoledMode.value = val; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(val ? 'AMOLED mode enabled' : 'AMOLED mode disabled'), duration: const Duration(seconds: 1))); },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.autoPause,
            builder: (context, value, _) => SwitchListTile(
              activeThumbColor: neonAccent, activeTrackColor: neonAccent.withValues(alpha: 0.3),
              title: const Text('Smart Auto-Pause', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), subtitle: const Text('Automatically pauses tracking when you stop moving', style: TextStyle(color: Colors.grey, fontSize: 12)),
              value: value, onChanged: (val) { AppSettings.autoPause.value = val; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(val ? 'Auto-Pause turned on' : 'Auto-Pause turned off'), duration: const Duration(seconds: 1))); },
            ),
          ),
          const Divider(color: Colors.white10, height: 32),
          _buildSectionHeader('Preferences'),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.metricUnits,
            builder: (context, value, _) => SwitchListTile(
              activeThumbColor: neonAccent, activeTrackColor: neonAccent.withValues(alpha: 0.3),
              title: const Text('Use Metric System', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), subtitle: Text(value ? 'Kilometers & Meters (km / m)' : 'Miles & Feet (mi / ft)', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              value: value, onChanged: (val) => AppSettings.metricUnits.value = val,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.backgroundTracking,
            builder: (context, value, _) => SwitchListTile(
              activeThumbColor: neonAccent, activeTrackColor: neonAccent.withValues(alpha: 0.3),
              title: const Text('Background Tracking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), subtitle: const Text('Allow GPS tracking service when screen is locked', style: TextStyle(color: Colors.grey, fontSize: 12)),
              value: value, onChanged: (val) => AppSettings.backgroundTracking.value = val,
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildSectionHeader(String title) { return Padding(padding: const EdgeInsets.only(left: 16, bottom: 8, top: 16), child: Text(title.toUpperCase(), style: const TextStyle(color: neonAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))); }
}

// ---------------------------------------------------------------------------
// 2. OFFLINE MAPS SCREEN
// ---------------------------------------------------------------------------
class ManageOfflineMapsScreen extends StatefulWidget {
  const ManageOfflineMapsScreen({super.key});
  @override State<ManageOfflineMapsScreen> createState() => _ManageOfflineMapsScreenState();
}

class _ManageOfflineMapsScreenState extends State<ManageOfflineMapsScreen> {
  List<Map<String, String>> downloadedMaps = [{'name': 'Current Base Region', 'size': '15.4 MB', 'date': 'Active Cache'}];

  void _deleteMap(int index) { final name = downloadedMaps[index]['name']; setState(() => downloadedMaps.removeAt(index)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cleared "$name" offline cache.'), backgroundColor: Colors.redAccent)); }
  void _clearAllCache() { showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: cardSurface, title: const Text('Clear All Offline Maps?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), content: const Text('This will remove all locally stored map tiles. You will need internet to view these areas again.', style: TextStyle(color: Colors.grey)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { Navigator.pop(ctx); setState(() => downloadedMaps.clear()); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All offline maps removed.'))); }, child: const Text('Clear All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))],)); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('Offline Maps', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: bgColor, elevation: 0, iconTheme: const IconThemeData(color: Colors.white), actions: [if (downloadedMaps.isNotEmpty) IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.redAccent), tooltip: 'Clear All', onPressed: _clearAllCache)]),
      body: Column(
        children: [
          Container(padding: const EdgeInsets.all(16), width: double.infinity, color: neonAccent.withValues(alpha: 0.05), child: const Column(children: [Icon(Icons.signal_cellular_connected_no_internet_4_bar, color: neonAccent, size: 32), SizedBox(height: 8), Text('Navigate without cellular service.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('Use the Download button on the Record Map to save specific trail regions.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12))])),
          Expanded(
            child: downloadedMaps.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.map_outlined, size: 54, color: Colors.grey[700]), const SizedBox(height: 12), const Text("No offline regions stored.", style: TextStyle(color: Colors.grey, fontSize: 15)), const SizedBox(height: 6), const Text("Go to the Record tab to download map sectors.", style: TextStyle(color: Colors.grey, fontSize: 12))]))
                : ListView.builder(
                    padding: const EdgeInsets.all(16), itemCount: downloadedMaps.length,
                    itemBuilder: (context, index) { final map = downloadedMaps[index]; return Card(color: cardSurface, margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: ListTile(contentPadding: const EdgeInsets.all(16), leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.map_outlined, color: neonAccent)), title: Text(map['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text('${map['size']} • ${map['date']}', style: const TextStyle(color: Colors.grey, fontSize: 12)), trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _deleteMap(index)))); },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. HELP & SUPPORT SCREEN
// ---------------------------------------------------------------------------
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _sendSupportEmail(BuildContext context) async {
    final Uri emailLaunchUri = Uri(scheme: 'mailto', path: 'support@xploretrails.com', queryParameters: {'subject': 'Xplore App Support Request', 'body': 'Hi Xplore Team,\n\nI need help with:\n'});
    try { if (await canLaunchUrl(emailLaunchUri)) { await launchUrl(emailLaunchUri); } else { if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support email: support@xploretrails.com'))); } } } catch (_) { if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open email app. Write to: support@xploretrails.com'))); } }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('Help & Support', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: bgColor, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(20)),
            child: Column(children: [const Icon(Icons.support_agent, size: 48, color: neonAccent), const SizedBox(height: 16), const Text('Need assistance on the trail?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('Our outdoor support team responds within 24 hours.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)), const SizedBox(height: 20), SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.email), label: const Text('Contact Support', style: TextStyle(fontWeight: FontWeight.bold)), onPressed: () => _sendSupportEmail(context)))]),
          ),
          const SizedBox(height: 24), const Text('Frequently Asked Questions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 12),
          _buildFAQItem('How do I import a GPX file?', 'You can import GPX files directly from the Explore tab by tapping the upload icon in the top right corner. The file will automatically parse and load ready for navigation.'),
          _buildFAQItem('How does offline tracking work?', 'As long as GPS is active, Xplore tracks your route and saves it to local SQLite storage. When you regain internet connection, the app automatically uploads pending treks.'),
          _buildFAQItem('What is AMOLED mode?', 'AMOLED mode blacks out all unneeded screen elements, shutting off individual OLED pixels to save battery on multi-day treks.'),
          const SizedBox(height: 32), Center(child: Text('Xplore Version 1.2.4\nEngineered for the Wilderness', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.withValues(alpha: 0.5), fontSize: 12)))
        ],
      ),
    );
  }
  Widget _buildFAQItem(String question, String answer) { return Card(color: cardSurface, margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: Theme(data: ThemeData(dividerColor: Colors.transparent), child: ExpansionTile(iconColor: neonAccent, collapsedIconColor: Colors.grey, title: Text(question, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)), children: [Padding(padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16), child: Text(answer, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)))]))); }
}