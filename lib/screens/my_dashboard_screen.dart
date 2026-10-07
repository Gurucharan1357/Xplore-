import 'package:flutter/material.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const MyApp());
}

// Global theme colors
const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Xplore Athlete Dashboard',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgColor,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: bgColor,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      home: const MyDashboardScreen(),
    );
  }
}

class MyDashboardScreen extends StatefulWidget {
  const MyDashboardScreen({super.key});

  @override
  State<MyDashboardScreen> createState() => _MyDashboardScreenState();
}

class _MyDashboardScreenState extends State<MyDashboardScreen> {
  String displayName = 'Alex';
  String username = '@alex_xplore';
  // Swapped to a CORS-friendly Unsplash URL for web testing
  final String avatarUrl = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=500&auto=format&fit=crop';

  List<Map<String, dynamic>> myTreks = [
    {
      'id': '1',
      'name': 'Lake Serenity Loop',
      'distance_meters': 8400,
      'elevation_gain': 320,
      'difficulty': 'Easy',
      'date': 'Oct 7, 2026',
      'image_url': 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?q=80&w=600&auto=format&fit=crop',
      'isHidden': false,
    },
    {
      'id': '2',
      'name': 'Pine Ridge Trail',
      'distance_meters': 12100,
      'elevation_gain': 540,
      'difficulty': 'Moderate',
      'date': 'Oct 2, 2026',
      'image_url': 'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?q=80&w=600&auto=format&fit=crop',
      'isHidden': false,
    },
    {
      'id': '3',
      'name': 'Summit Pass',
      'distance_meters': 18500,
      'elevation_gain': 1120,
      'difficulty': 'Hard',
      'date': 'Sep 28, 2026',
      'image_url': 'https://images.unsplash.com/photo-1454496522488-7a8e488e8606?q=80&w=600&auto=format&fit=crop',
      'isHidden': false,
    }
  ];

  void _hideTrail(String id) {
    setState(() {
      final index = myTreks.indexWhere((t) => t['id'] == id);
      if (index != -1) {
        myTreks[index]['isHidden'] = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trail hidden from your profile.')));
  }

  void _restoreHiddenTrails() {
    setState(() {
      for (var trek in myTreks) {
        trek['isHidden'] = false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All hidden trails restored!')));
  }

  void _showProfileImagePopup() {
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
                  avatarUrl, 
                  width: MediaQuery.of(context).size.width * 0.85, 
                  height: MediaQuery.of(context).size.width * 0.85, 
                  fit: BoxFit.cover,
                  // Crash prevention if image fails
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    height: MediaQuery.of(context).size.width * 0.85,
                    color: cardSurface,
                    child: const Icon(Icons.person, size: 100, color: Colors.grey),
                  ),
                )
              )
            ),
          ),
        ),
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: displayName);
    final userCtrl = TextEditingController(text: username.replaceAll('@', ''));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: neonAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () { setState(() { displayName = nameCtrl.text; username = '@${userCtrl.text}'; }); Navigator.pop(ctx); }, child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold))),
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
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white), 
              title: const Text('App Settings', style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSettingsScreen())); }
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline, color: Colors.white), 
              title: const Text('Manage Offline Maps', style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageOfflineMapsScreen())); }
            ),
            ListTile(
              leading: const Icon(Icons.help_outline, color: Colors.white), 
              title: const Text('Help & Support', style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen())); }
            ),
            const Divider(color: Colors.white10),
            ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: () => Navigator.pop(ctx)),
          ],
        ),
      )
    );
  }

  void _showCommunityList(String title) {
    final List<Map<String, String>> mockUsers = [
      {'name': 'Sarah Jenkins', 'username': '@sarah_j', 'avatar': 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?q=80&w=150&auto=format&fit=crop', 'isFollowing': 'true'},
      {'name': 'Mike Chen', 'username': '@mike_hikes', 'avatar': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?q=80&w=150&auto=format&fit=crop', 'isFollowing': 'false'},
    ];
    showModalBottomSheet(
      context: context, backgroundColor: cardSurface, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (context, setSheetState) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8), itemCount: mockUsers.length,
                  itemBuilder: (context, index) {
                    final user = mockUsers[index];
                    final isFollowing = user['isFollowing'] == 'true';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage(user['avatar']!), 
                        backgroundColor: Colors.grey[800],
                        // Graceful fallback
                        onBackgroundImageError: (e, s) => {},
                      ),
                      title: Text(user['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(user['username']!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: GestureDetector(
                        onTap: () => setSheetState(() => user['isFollowing'] = isFollowing ? 'false' : 'true'),
                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: isFollowing ? Colors.transparent : neonAccent, border: isFollowing ? Border.all(color: Colors.grey) : null, borderRadius: BorderRadius.circular(20)), child: Text(isFollowing ? 'Following' : 'Follow', style: TextStyle(color: isFollowing ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTreks = myTreks.where((t) => t['isHidden'] == false).toList();
    final hasHiddenTreks = myTreks.any((t) => t['isHidden'] == true);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            // 1. HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _showProfileImagePopup,
                      child: Hero(
                        tag: 'avatar_hero', 
                        child: Container(
                          padding: const EdgeInsets.all(2), 
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: neonAccent, width: 2)), 
                          child: CircleAvatar(
                            radius: 28, 
                            backgroundColor: Colors.grey[800], 
                            backgroundImage: NetworkImage(avatarUrl),
                            onBackgroundImageError: (e, s) => {}, // Prevents crashing
                          )
                        )
                      ),
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
            const SizedBox(height: 32),

            // 2. LIFETIME STATS
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
                      _buildHeroStat('Total Dist', '184.2', 'km'),
                      _buildHeroStat('Total Elev', '4,210', 'm'),
                      _buildHeroStat('Treks', '24', ''),
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

            // 3. COMMUNITY
            Row(
              children: [
                Expanded(child: _buildCommunityPill('142', 'Followers', () => _showCommunityList('Followers'))),
                const SizedBox(width: 16),
                Expanded(child: _buildCommunityPill('84', 'Following', () => _showCommunityList('Following'))),
              ],
            ),
            const SizedBox(height: 32),

            // 4. MY RECORDED TRAILS HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("My Recorded Trails", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (hasHiddenTreks)
                  TextButton(onPressed: _restoreHiddenTrails, child: const Text("Show Trails", style: TextStyle(color: neonAccent, fontSize: 13, fontWeight: FontWeight.bold)))
              ],
            ),
            const SizedBox(height: 12),
            
            // 5. CONTENT AREA
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
    );
  }

  Widget _buildHeroStat(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), if (unit.isNotEmpty) Text(' $unit', style: const TextStyle(color: Colors.grey, fontSize: 12))],
        )
      ],
    );
  }

  Widget _buildCommunityPill(String number, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [Text(number, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))]),
      ),
    );
  }

  Widget _buildEmptyTrailsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.transparent, 
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10, width: 1.5), 
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: cardSurface, shape: BoxShape.circle),
            child: const Icon(Icons.landscape, size: 48, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          const Text("No trails recorded yet", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text("Hit the trail and record your first adventure. Upload photos and build your lifetime stats.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: neonAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)
            ),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('Record a Trek', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jumping to Record Screen...')));
            },
          )
        ],
      ),
    );
  }

  Widget _buildMyTrailCard(Map<String, dynamic> trek) {
    final distKm = (trek['distance_meters'] / 1000).toStringAsFixed(1);
    
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(20)),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                  stops: const [0.3, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.darken,
              child: Image.network(
                trek['image_url'], 
                height: double.infinity, 
                width: double.infinity, 
                fit: BoxFit.cover,
                // Crash prevention if image fails
                errorBuilder: (context, error, stackTrace) => Container(color: bgColor, child: const Icon(Icons.terrain, color: Colors.white24, size: 48)),
              ),
            ),
          ),
          
          Positioned(
            top: 12, left: 12, right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                  child: Text(trek['date'], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting GPX file...'))),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                        child: const Icon(Icons.ios_share, color: Colors.white, size: 16), 
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.zero,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                        color: cardSurface,
                        onSelected: (value) {
                          if (value == 'Hide') {
                            _hideTrail(trek['id']);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$value Selected')));
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(value: 'Edit', child: Text('Edit Details')),
                          const PopupMenuItem<String>(value: 'Hide', child: Text('Hide from Profile')),
                          const PopupMenuItem<String>(value: 'Delete', child: Text('Delete Trek', style: TextStyle(color: Colors.redAccent))),
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),

          Positioned(
            bottom: 16, left: 16, right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trek['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.straighten, color: neonAccent, size: 14),
                    const SizedBox(width: 4),
                    Text('$distKm km', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(width: 12),
                    const Icon(Icons.trending_up, color: neonAccent, size: 14),
                    const SizedBox(width: 4),
                    Text('${trek['elevation_gain']}m', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. SETTINGS SCREEN
// ---------------------------------------------------------------------------
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool amoledMode = true;
  bool autoPause = true;
  bool metricUnits = true;
  bool backgroundTracking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSectionHeader('Map & Navigation'),
          SwitchListTile(
            activeThumbColor: neonAccent,
            activeTrackColor: neonAccent.withValues(alpha: 0.3),
            title: const Text('AMOLED Battery Saver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: const Text('Forces map to pure black when tracking', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: amoledMode,
            onChanged: (val) => setState(() => amoledMode = val),
          ),
          SwitchListTile(
            activeThumbColor: neonAccent,
            activeTrackColor: neonAccent.withValues(alpha: 0.3),
            title: const Text('Smart Auto-Pause', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: const Text('Automatically pauses tracking when you stop moving', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: autoPause,
            onChanged: (val) => setState(() => autoPause = val),
          ),
          const Divider(color: Colors.white10, height: 32),
          _buildSectionHeader('Preferences'),
          SwitchListTile(
            activeThumbColor: neonAccent,
            activeTrackColor: neonAccent.withValues(alpha: 0.3),
            title: const Text('Use Metric System', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text(metricUnits ? 'Currently using Kilometers & Meters' : 'Currently using Miles & Feet', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            value: metricUnits,
            onChanged: (val) => setState(() => metricUnits = val),
          ),
          SwitchListTile(
            activeThumbColor: neonAccent,
            activeTrackColor: neonAccent.withValues(alpha: 0.3),
            title: const Text('Background Tracking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: const Text('Allow GPS to run when screen is locked', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: backgroundTracking,
            onChanged: (val) => setState(() => backgroundTracking = val),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 16),
      child: Text(title.toUpperCase(), style: const TextStyle(color: neonAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. OFFLINE MAPS SCREEN
// ---------------------------------------------------------------------------
class ManageOfflineMapsScreen extends StatefulWidget {
  const ManageOfflineMapsScreen({super.key});

  @override
  State<ManageOfflineMapsScreen> createState() => _ManageOfflineMapsScreenState();
}

class _ManageOfflineMapsScreenState extends State<ManageOfflineMapsScreen> {
  List<Map<String, String>> downloadedMaps = [
    {'name': 'Lake Serenity Region', 'size': '14.2 MB', 'date': 'Downloaded Oct 2'},
    {'name': 'Pine Ridge Wilderness', 'size': '38.5 MB', 'date': 'Downloaded Sep 15'},
  ];

  void _deleteMap(int index) {
    setState(() {
      downloadedMaps.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline map deleted.', style: TextStyle(color: Colors.white))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Maps')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: neonAccent.withValues(alpha: 0.05),
            child: const Column(
              children: [
                Icon(Icons.signal_cellular_connected_no_internet_4_bar, color: neonAccent, size: 32),
                SizedBox(height: 8),
                Text('Navigate without cellular service.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Select an area on the map screen to download.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: downloadedMaps.isEmpty
                ? const Center(child: Text("No offline maps saved.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: downloadedMaps.length,
                    itemBuilder: (context, index) {
                      final map = downloadedMaps[index];
                      return Card(
                        color: cardSurface,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.map_outlined, color: neonAccent),
                          ),
                          title: Text(map['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text('${map['size']} • ${map['date']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _deleteMap(index),
                          ),
                        ),
                      );
                    },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                const Icon(Icons.support_agent, size: 48, color: neonAccent),
                const SizedBox(height: 16),
                const Text('Need assistance on the trail?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Our support team usually responds within 24 hours.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: neonAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.email),
                    label: const Text('Contact Support', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {},
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Frequently Asked Questions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _buildFAQItem('How do I import a GPX file?', 'You can import GPX files directly from the Explore tab by tapping the upload icon in the top right corner. The file will automatically parse and be ready for turn-by-turn navigation.'),
          _buildFAQItem('How does offline tracking work?', 'As long as you have GPS signal, Xplore will track your route and save it to your device. Once you regain cellular connection, open the app to automatically sync it to the cloud.'),
          _buildFAQItem('What is AMOLED mode?', 'AMOLED mode turns the map completely black, turning off the pixels on OLED screens. This saves significant battery life on long wilderness treks.'),
          const SizedBox(height: 32),
          Center(
            child: Text('Xplore Version 1.2.4\nMade for the Wilderness', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.withValues(alpha: 0.5), fontSize: 12)),
          )
        ],
      ),
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return Card(
      color: cardSurface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: neonAccent,
          collapsedIconColor: Colors.grey,
          title: Text(question, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Text(answer, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
            )
          ],
        ),
      ),
    );
  }
}

// Sparkline Custom Painter
class _NeonSparklinePainter extends CustomPainter {
  final Color color;
  _NeonSparklinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final List<double> data = [0.2, 0.4, 0.3, 0.6, 0.5, 0.8, 0.7, 0.9, 0.8, 1.0];
    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (data.length - 1);
    
    path.moveTo(0, size.height - (data[0] * size.height));
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, size.height - (data[0] * size.height));

    for (int i = 1; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - (data[i] * size.height);
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }
    
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final paintFill = Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, size.height), [color.withValues(alpha: 0.4), color.withValues(alpha: 0.0)]);
    canvas.drawPath(fillPath, paintFill);

    final paintStroke = Paint()..color = color..strokeWidth = 3.0..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke;
    canvas.drawPath(path, paintStroke);
    
    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(0, size.height - (data[0] * size.height)), 4, dotPaint);
    canvas.drawCircle(Offset(size.width, size.height - (data.last * size.height)), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}