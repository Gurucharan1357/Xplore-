import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart'; 
import 'package:xplore_mobile/main.dart'; 
import 'package:xplore_mobile/screens/trail_detail_screen.dart';
import 'package:xplore_mobile/screens/public_profile_screen.dart'; 
import 'package:url_launcher/url_launcher.dart';
import 'package:xplore_mobile/screens/saved_trails_screen.dart'; 
import 'package:xplore_mobile/utils/offline_sync_manager.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);
const String styleDark = 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';

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
  int _pendingSyncCount = 0;

  int _selectedTrailTab = 0; // 0: Public, 1: Followers Only/Private

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    _checkCrashRecovery();
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
      
      final List<dynamic> trekData = await Supabase.instance.client
          .from('completed_treks')
          .select()
          .eq('user_id', currentUserId)
          .order('created_at', ascending: false);
      
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
            'name': t['trek_name'],
            // Safely convert strings to numbers to prevent TrailDetailScreen crash
            'distance_meters': (double.tryParse(t['distance']?.toString() ?? '0') ?? 0) * 1000,
            'elevation_gain': double.tryParse(t['elevation_gain']?.toString() ?? '0') ?? 0,
            'route_geom': t['recorded_route'] 
          }).toList();

          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCommunityList(String title, bool isFollowers) {
    Future<List<dynamic>> usersFuture = _getCommunityUsers(isFollowers);

    showModalBottomSheet(
      context: context, backgroundColor: cardSurface, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Padding(padding: const EdgeInsets.all(20.0), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                const Divider(color: Colors.white10, height: 1),
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: usersFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: neonAccent));
                      final users = snapshot.data ?? [];
                      if (users.isEmpty) return Center(child: Text('No $title yet.', style: const TextStyle(color: Colors.grey)));
                      return ListView.builder(
                        controller: scrollController, itemCount: users.length,
                        itemBuilder: (context, index) {
                          final u = users[index];
                          final avatar = u['avatar_url'];
                          return ListTile(
                            leading: CircleAvatar(backgroundColor: neonAccent, backgroundImage: avatar != null ? NetworkImage(avatar) : null, child: avatar == null ? const Icon(Icons.person, color: Colors.black) : null),
                            title: Text(u['display_name'] ?? 'Athlete', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(u['username'] != null ? '@${u['username']}' : '', style: const TextStyle(color: Colors.grey)),
                            trailing: TextButton(
                              style: TextButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), minimumSize: Size.zero),
                              onPressed: () async {
                                final myId = Supabase.instance.client.auth.currentUser!.id;
                                try {
                                  if (isFollowers) await Supabase.instance.client.from('follows').delete().eq('follower_id', u['id']).eq('following_id', myId);
                                  else await Supabase.instance.client.from('follows').delete().eq('follower_id', myId).eq('following_id', u['id']);
                                  setSheetState(() => usersFuture = _getCommunityUsers(isFollowers));
                                  _fetchDashboardData();
                                } catch (_) {}
                              },
                              child: Text(isFollowers ? 'Remove' : 'Unfollow', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: u['id']))); },
                          );
                        }
                      );
                    }
                  ),
                )
              ],
            );
          }
        )
      )
    );
  }

  Future<List<dynamic>> _getCommunityUsers(bool isFollowers) async {
    final client = Supabase.instance.client;
    final myId = client.auth.currentUser!.id;
    List<dynamic> followData = isFollowers ? await client.from('follows').select('follower_id').eq('following_id', myId) : await client.from('follows').select('following_id').eq('follower_id', myId);
    if (followData.isEmpty) return [];
    final ids = followData.map((e) => e[isFollowers ? 'follower_id' : 'following_id'].toString()).toList();
    return await client.from('profiles').select().inFilter('id', ids);
  }
  
  Future<void> _pickAndUploadAvatar() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1000, maxHeight: 1000, imageQuality: 85);
      if (image == null) return; 
      setState(() => _isLoading = true);
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final fileExtension = image.path.split('.').last.toLowerCase();
      final fileName = 'avatar_$userId.${fileExtension == 'jpg' ? 'jpeg' : fileExtension}';
      await Supabase.instance.client.storage.from('Avatars').upload(fileName, File(image.path), fileOptions: const FileOptions(upsert: true));
      final String publicUrl = Supabase.instance.client.storage.from('Avatars').getPublicUrl(fileName);
      await Supabase.instance.client.from('profiles').update({'avatar_url': '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}'}).eq('id', userId);
      _fetchDashboardData();
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    final syncedCount = await OfflineSyncManager.syncPending(); 
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(syncedCount > 0 ? 'Successfully synced $syncedCount treks!' : 'Network still unavailable.'), backgroundColor: syncedCount > 0 ? Colors.green : Colors.orange));
      setState(() => _isSyncing = false);
      _fetchDashboardData(); 
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
    setState(() { for (var trek in _myTreks) { trek['isHidden'] = false; } });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All hidden trails restored!')));
  }

  void _showProfileImagePopup(String avatarUrl) {
    showDialog(
      context: context, barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Center(child: GestureDetector(onTap: () => Navigator.pop(ctx), child: Hero(tag: 'avatar_hero', child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.network(avatarUrl, width: MediaQuery.of(context).size.width * 0.85, height: MediaQuery.of(context).size.width * 0.85, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(width: MediaQuery.of(context).size.width * 0.85, height: MediaQuery.of(context).size.width * 0.85, color: cardSurface, child: const Icon(Icons.person, size: 100, color: Colors.grey))))))),
    );
  }

 void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _userProfile?['display_name'] ?? '');
    final userCtrl = TextEditingController(text: _userProfile?['username'] ?? '');
    final bioCtrl = TextEditingController(text: _userProfile?['bio'] ?? ''); 

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Display Name', labelStyle: TextStyle(color: Colors.grey), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: neonAccent)))), const SizedBox(height: 16),
            TextField(controller: userCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Username', prefixText: '@ ', labelStyle: TextStyle(color: Colors.grey), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: neonAccent)))), const SizedBox(height: 16),
            TextField(controller: bioCtrl, style: const TextStyle(color: Colors.white, fontSize: 14), maxLength: 150, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Bio', labelStyle: TextStyle(color: Colors.grey), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: neonAccent)), counterStyle: TextStyle(color: Colors.grey, fontSize: 10))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () async { try { await Supabase.instance.client.from('profiles').update({'display_name': nameCtrl.text.trim(), 'username': userCtrl.text.trim(), 'bio': bioCtrl.text.trim()}).eq('id', Supabase.instance.client.auth.currentUser!.id); Navigator.pop(ctx); _fetchDashboardData(); } catch (_) {} }, child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold))),
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
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))), const SizedBox(height: 24),
            ListTile(leading: const Icon(Icons.bookmark, color: neonAccent), title: const Text('Saved Trails', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedTrailsScreen())); }),
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
    if (_isLoading) return const Scaffold(backgroundColor: bgColor, body: Center(child: CircularProgressIndicator(color: neonAccent)));

    final displayName = _userProfile?['display_name'] ?? 'Athlete';
    final username = '@${_userProfile?['username'] ?? 'explorer'}';
    final avatarUrl = _userProfile?['avatar_url'] ?? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=500&auto=format&fit=crop';

    final totalDistanceKm = _myTreks.fold<double>(0.0, (acc, item) => acc + (double.tryParse(item['distance']?.toString() ?? '0') ?? 0.0));
    final totalElevationM = _myTreks.fold<double>(0.0, (acc, item) => acc + (double.tryParse(item['elevation_gain']?.toString() ?? '0') ?? 0.0));
    
    // Filter the horizontal list based on Public / Private Toggle
    final visibleTreks = _myTreks.where((t) {
      if (t['isHidden'] == true) return false;
      bool isPublic = t['is_public'] ?? true;
      return _selectedTrailTab == 0 ? isPublic : !isPublic;
    }).toList();

    final hasHiddenTreks = _myTreks.any((t) => t['isHidden'] == true);

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: neonAccent, backgroundColor: cardSurface, onRefresh: _fetchDashboardData,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              // User Header Profile Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            GestureDetector(onTap: () => _showProfileImagePopup(avatarUrl), child: Hero(tag: 'avatar_hero', child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: neonAccent, width: 2)), child: CircleAvatar(radius: 34, backgroundColor: Colors.grey[800], backgroundImage: NetworkImage(avatarUrl), onBackgroundImageError: (e, s) => {})))),
                            Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _pickAndUploadAvatar, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: neonAccent, shape: BoxShape.circle, border: Border.all(color: bgColor, width: 2)), child: const Icon(Icons.camera_alt, color: Colors.black, size: 14))))
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('My Dashboard', style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1)), const SizedBox(height: 2),
                              Row(children: [Expanded(child: Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)), const SizedBox(width: 8), GestureDetector(onTap: _showEditProfileDialog, child: const Icon(Icons.edit_square, color: neonAccent, size: 16))]),
                              Text(username, style: TextStyle(color: neonAccent.withValues(alpha: 0.7), fontSize: 13)),
                              if (_userProfile?['bio'] != null && _userProfile!['bio'].toString().trim().isNotEmpty) ...[const SizedBox(height: 8), Text(_userProfile!['bio'], style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(onTap: _showSettingsMenu, child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: cardSurface, shape: BoxShape.circle), child: const Icon(Icons.menu, color: Colors.white, size: 22)))
                ],
              ),
              
              if (_pendingSyncCount > 0)
                Container(margin: const EdgeInsets.only(top: 24, bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange.withValues(alpha: 0.5))), child: Row(children: [const Icon(Icons.cloud_off, color: Colors.orange), const SizedBox(width: 12), Expanded(child: Text('$_pendingSyncCount treks waiting to sync.', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))), _isSyncing ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2)) : TextButton(onPressed: _triggerSync, child: const Text('Sync', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)))]) )
              else const SizedBox(height: 32),

              const Text("Lifetime Stats", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildHeroStat('Total Dist', totalDistanceKm.toStringAsFixed(1), 'km'), _buildHeroStat('Total Elev', totalElevationM.toStringAsFixed(0), 'm'), _buildHeroStat('Treks', '${_myTreks.length}', '')]),
                    const SizedBox(height: 24), const Row(children: [Icon(Icons.show_chart, color: neonAccent, size: 16), SizedBox(width: 6), Text('Recent Elevation Progress', style: TextStyle(color: Colors.grey, fontSize: 12))]), const SizedBox(height: 12),
                    SizedBox(height: 60, width: double.infinity, child: CustomPaint(painter: _NeonSparklinePainter(neonAccent))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Row(children: [Expanded(child: _buildCommunityPill('$_followersCount', 'Followers', () => _showCommunityList('Followers', true))), const SizedBox(width: 16), Expanded(child: _buildCommunityPill('$_followingCount', 'Following', () => _showCommunityList('Following', false)))]),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("My Recorded Trails", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (hasHiddenTreks) TextButton(onPressed: _restoreHiddenTrails, child: const Text("Show Hidden", style: TextStyle(color: neonAccent, fontSize: 13, fontWeight: FontWeight.bold)))
                ],
              ),
              const SizedBox(height: 12),

              // Animated Segmented Toggle (Public / Private)
              Container(
                height: 48, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                child: Stack(
                  children: [
                    AnimatedAlign(
                      alignment: _selectedTrailTab == 0 ? Alignment.centerLeft : Alignment.centerRight, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic,
                      child: FractionallySizedBox(widthFactor: 0.5, child: Container(margin: const EdgeInsets.all(4), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(8), border: Border.all(color: neonAccent.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))]))),
                    ),
                    Row(
                      children: [
                        Expanded(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _selectedTrailTab = 0), child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 250), style: TextStyle(color: _selectedTrailTab == 0 ? neonAccent : Colors.grey, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: DefaultTextStyle.of(context).style.fontFamily), child: const Text('Public'))))),
                        Expanded(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _selectedTrailTab = 1), child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 250), style: TextStyle(color: _selectedTrailTab == 1 ? neonAccent : Colors.grey, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: DefaultTextStyle.of(context).style.fontFamily), child: const Text('Followers Only'))))),
                      ],
                    ),
                  ],
                ),
              ),
              
              visibleTreks.isEmpty 
                ? _buildEmptyTrailsState() 
                : SizedBox(
                    height: 260,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: visibleTreks.length,
                      itemBuilder: (context, index) {
                        return _HorizontalTrailCard(
                          trek: visibleTreks[index],
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(
                              trek: visibleTreks[index], 
                              onStartTrail: () { if (widget.onSelectTrek != null) widget.onSelectTrek!(visibleTreks[index]); }
                            )));
                          },
                          onHide: () => _hideTrail(visibleTreks[index]['id']),
                          onDelete: () async {
                            await Supabase.instance.client.from('completed_treks').delete().eq('id', visibleTreks[index]['id']);
                            _fetchDashboardData();
                          },
                        );
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
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 0.5)), const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), if (unit.isNotEmpty) Text(' $unit', style: const TextStyle(color: Colors.grey, fontSize: 12))])
      ],
    );
  }

  Widget _buildCommunityPill(String number, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: Column(children: [Text(number, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))])),
      ),
    );
  }

  Widget _buildEmptyTrailsState() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24), decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10, width: 1.5)),
      child: Column(
        children: [
          Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: cardSurface, shape: BoxShape.circle), child: const Icon(Icons.landscape, size: 48, color: Colors.grey)), const SizedBox(height: 24),
          Text(_selectedTrailTab == 0 ? "No public trails yet" : "No private trails yet", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
          Text(_selectedTrailTab == 0 ? "Record a trail and share it with the world!" : "Private trails are only visible to your followers.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HORIZONTAL CARD WIDGET WITH MAP OVERVIEW SUPPORT
// ---------------------------------------------------------------------------
class _HorizontalTrailCard extends StatefulWidget {
  final Map<String, dynamic> trek;
  final VoidCallback onTap;
  final VoidCallback onHide;
  final VoidCallback onDelete;

  const _HorizontalTrailCard({
    required this.trek, required this.onTap, required this.onHide, required this.onDelete
  });

  @override
  State<_HorizontalTrailCard> createState() => _HorizontalTrailCardState();
}

class _HorizontalTrailCardState extends State<_HorizontalTrailCard> {
  MapLibreMapController? _mapController;

  void _onStyleLoaded() async {
    if (_mapController == null) return;
    try {
      List<LatLng> pts = [];
      final routeData = widget.trek['route_geom'];
      if (routeData == null) return;

      if (routeData is String) {
        final decoded = jsonDecode(routeData);
        final coordinates = decoded['coordinates'] ?? decoded['geometry']?['coordinates'] ?? [];
        pts = coordinates.map<LatLng>((c) => LatLng(c[1] as double, c[0] as double)).toList();
      } else if (routeData is Map) {
        final coordinates = routeData['coordinates'] ?? routeData['geometry']?['coordinates'] ?? [];
        pts = coordinates.map<LatLng>((c) => LatLng(c[1] as double, c[0] as double)).toList();
      } else if (routeData is List) {
        pts = routeData.map<LatLng>((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final distKm = widget.trek['distance']?.toString() ?? '0.0';
    final elevM = widget.trek['elevation_gain']?.toString() ?? '0';
    final dateRaw = DateTime.parse(widget.trek['created_at'] ?? DateTime.now().toIso8601String());
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[dateRaw.month - 1]} ${dateRaw.day}, ${dateRaw.year}';
    final imageUrl = widget.trek['image_url'];
    final isPublic = widget.trek['is_public'] ?? true;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 260, margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ShaderMask(
                shaderCallback: (rect) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)], stops: const [0.3, 1.0]).createShader(rect),
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
              top: 12, left: 12, right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)), child: Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle), child: Icon(isPublic ? Icons.public : Icons.lock, color: Colors.white, size: 12)),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.zero, decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white, size: 18), color: cardSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (value) async {
                        if (value == 'Hide') widget.onHide();
                        else if (value == 'Delete') widget.onDelete();
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
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
                  Text(widget.trek['name'] ?? 'Wilderness Trek', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
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

class OfflineMapCache { static List<Map<String, String>> downloadedMaps = [{'name': 'Current Base Region', 'size': '15.4 MB', 'date': 'Active Cache'}]; }
class AppSettings { static final ValueNotifier<bool> amoledMode = ValueNotifier<bool>(false); static final ValueNotifier<bool> autoPause = ValueNotifier<bool>(true); static final ValueNotifier<bool> metricUnits = ValueNotifier<bool>(true); static final ValueNotifier<bool> backgroundTracking = ValueNotifier<bool>(true); }

class AppSettingsScreen extends StatefulWidget { const AppSettingsScreen({super.key}); @override State<AppSettingsScreen> createState() => _AppSettingsScreenState(); }
class _AppSettingsScreenState extends State<AppSettingsScreen> { @override Widget build(BuildContext context) { return Scaffold(backgroundColor: bgColor, appBar: AppBar(title: const Text('App Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: bgColor, elevation: 0), body: const Center(child: Text('Settings Here', style: TextStyle(color: Colors.grey)))); } }

class ManageOfflineMapsScreen extends StatefulWidget { const ManageOfflineMapsScreen({super.key}); @override State<ManageOfflineMapsScreen> createState() => _ManageOfflineMapsScreenState(); }
class _ManageOfflineMapsScreenState extends State<ManageOfflineMapsScreen> { @override Widget build(BuildContext context) { return Scaffold(backgroundColor: bgColor, appBar: AppBar(title: const Text('Offline Maps', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: bgColor, elevation: 0), body: const Center(child: Text('Offline Maps Here', style: TextStyle(color: Colors.grey)))); } }

class HelpSupportScreen extends StatelessWidget { const HelpSupportScreen({super.key}); @override Widget build(BuildContext context) { return Scaffold(backgroundColor: bgColor, appBar: AppBar(title: const Text('Support', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: bgColor, elevation: 0), body: const Center(child: Text('Support Screen', style: TextStyle(color: Colors.grey)))); } }