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
      title: 'Xplore Public Profile',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgColor,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: bgColor,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const PublicProfileScreen(),
    );
  }
}

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  // Mock Data for another user
  final String displayName = 'Sarah Jenkins';
  final String username = '@sarah_j';
  final String avatarUrl = 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?q=80&w=500&auto=format&fit=crop';
  
  bool isFollowing = false; // Toggle for the follow button

  // Only PUBLIC trails are fetched for this view
  final List<Map<String, dynamic>> publicTreks = [
    {
      'id': '101',
      'name': 'Glacier Point',
      'distance_meters': 14200,
      'elevation_gain': 890,
      'difficulty': 'Hard',
      'date': 'Oct 5, 2026',
      'image_url': 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?q=80&w=600&auto=format&fit=crop',
    },
    {
      'id': '102',
      'name': 'Echo Valley',
      'distance_meters': 6500,
      'elevation_gain': 210,
      'difficulty': 'Easy',
      'date': 'Sep 20, 2026',
      'image_url': 'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?q=80&w=600&auto=format&fit=crop',
    },
  ];

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
              tag: 'public_avatar_hero', 
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24), 
                child: Image.network(
                  avatarUrl, 
                  width: MediaQuery.of(context).size.width * 0.85, 
                  height: MediaQuery.of(context).size.width * 0.85, 
                  fit: BoxFit.cover,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Going back to Explore Feed')));
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {
              // Simple public options like Report or Block
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Options menu opened')));
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
        children: [
          // 1. PUBLIC HEADER
          Row(
            children: [
              GestureDetector(
                onTap: _showProfileImagePopup,
                child: Hero(
                  tag: 'public_avatar_hero', 
                  child: Container(
                    padding: const EdgeInsets.all(2), 
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isFollowing ? neonAccent : Colors.transparent, width: 2)), 
                    child: CircleAvatar(
                      radius: 36, 
                      backgroundColor: Colors.grey[800], 
                      backgroundImage: NetworkImage(avatarUrl),
                      onBackgroundImageError: (e, s) => {},
                    )
                  )
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(username, style: TextStyle(color: neonAccent.withValues(alpha: 0.8), fontSize: 14)),
                    const SizedBox(height: 12),
                    
                    // Public Follow Button
                    SizedBox(
                      height: 36,
                      width: 140,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFollowing ? Colors.transparent : neonAccent,
                          foregroundColor: isFollowing ? Colors.white : Colors.black,
                          elevation: 0,
                          side: BorderSide(color: isFollowing ? Colors.grey : neonAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () {
                          setState(() {
                            isFollowing = !isFollowing;
                          });
                        },
                        child: Text(
                          isFollowing ? 'Following' : 'Follow', 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                    _buildHeroStat('Total Dist', '412.5', 'km'),
                    _buildHeroStat('Total Elev', '8,900', 'm'),
                    _buildHeroStat('Treks', '47', ''),
                  ],
                ),
                const SizedBox(height: 24),
                const Row(children: [Icon(Icons.show_chart, color: neonAccent, size: 16), SizedBox(width: 6), Text('Elevation Progress', style: TextStyle(color: Colors.grey, fontSize: 12))]),
                const SizedBox(height: 12),
                SizedBox(height: 60, width: double.infinity, child: CustomPaint(painter: _NeonSparklinePainter(neonAccent))),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3. COMMUNITY
          Row(
            children: [
              Expanded(child: _buildCommunityPill('3,402', 'Followers')),
              const SizedBox(width: 16),
              Expanded(child: _buildCommunityPill('128', 'Following')),
            ],
          ),
          const SizedBox(height: 32),

          // 4. PUBLIC TRAILS HEADER
          const Text("Recent Trails", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          // 5. READ-ONLY TRAIL CARDS
          publicTreks.isEmpty 
            ? _buildEmptyState()
            : SizedBox(
                height: 260,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: publicTreks.length,
                  itemBuilder: (context, index) {
                    return _buildPublicTrailCard(publicTreks[index]);
                  },
                ),
              )
        ],
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

  Widget _buildCommunityPill(String number, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [Text(number, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))]),
    );
  }

  Widget _buildEmptyState() {
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
          const Text("No public trails", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text("$displayName hasn't made any trails public yet.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildPublicTrailCard(Map<String, dynamic> trek) {
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
                errorBuilder: (context, error, stackTrace) => Container(color: bgColor, child: const Icon(Icons.terrain, color: Colors.white24, size: 48)),
              ),
            ),
          ),
          
          // No 3-dot menu here, just the date and a share button
          Positioned(
            top: 12, left: 12, right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                  child: Text(trek['date'], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sharing public trail...'))),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                    child: const Icon(Icons.ios_share, color: Colors.white, size: 16), 
                  ),
                ),
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

// Sparkline Custom Painter
class _NeonSparklinePainter extends CustomPainter {
  final Color color;
  _NeonSparklinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final List<double> data = [0.1, 0.2, 0.4, 0.3, 0.7, 0.5, 0.9, 0.8, 0.95, 1.0];
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