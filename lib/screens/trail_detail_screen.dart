import 'package:flutter/material.dart';
import 'dart:ui' as ui;

// Assuming these are defined in a central theme file, or keep them here:
const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class TrailDetailScreen extends StatefulWidget {
  // 1. ADDED: The screen now requires trek data to be passed in!
  final Map<String, dynamic> trek;

  const TrailDetailScreen({super.key, required this.trek});

  @override
  State<TrailDetailScreen> createState() => _TrailDetailScreenState();
}

class _TrailDetailScreenState extends State<TrailDetailScreen> {
  bool isBookmarked = false;
  bool isDownloaded = false;

  @override
  Widget build(BuildContext context) {
    // 2. ADDED: Extract real data from the passed 'trek' map
    // (Using fallbacks just in case a field is missing in your database)
    final heroImageUrl = widget.trek['image_url'] ?? 'https://images.unsplash.com/photo-1454496522488-7a8e488e8606?q=80&w=1000&auto=format&fit=crop';
    final trailName = widget.trek['name'] ?? 'Unknown Trail';
    final difficulty = widget.trek['difficulty'] ?? 'Moderate';
    
    // Formatting numbers
    final distKm = widget.trek['distance_meters'] != null 
        ? (widget.trek['distance_meters'] / 1000).toStringAsFixed(1) 
        : '0.0';
    final elevation = widget.trek['elevation_gain'] != null 
        ? '${widget.trek['elevation_gain']} m' 
        : '0 m';

    // Placeholder for creator (until you fetch it from profiles table)
    final creatorName = 'Creator';
    final creatorUsername = '@explorer';
    final creatorAvatar = 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?q=80&w=200&auto=format&fit=crop';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280.0,
            pinned: true,
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              // 3. ADDED: Real back button functionality
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                  child: const Icon(Icons.ios_share, color: Colors.white, size: 20),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting...')));
                },
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                  child: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border, color: isBookmarked ? neonAccent : Colors.white, size: 20),
                ),
                onPressed: () => setState(() => isBookmarked = !isBookmarked),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    heroImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(color: cardSurface, child: const Icon(Icons.terrain, size: 64, color: Colors.white24)),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, bgColor],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                ],
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(trailName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.2)),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 16, top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: difficulty.toUpperCase() == 'HARD' ? Colors.redAccent.withValues(alpha: 0.2) : neonAccent.withValues(alpha: 0.2),
                          border: Border.all(color: difficulty.toUpperCase() == 'HARD' ? Colors.redAccent : neonAccent),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(difficulty.toUpperCase(), style: TextStyle(color: difficulty.toUpperCase() == 'HARD' ? Colors.redAccent : neonAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening Profile...')));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.grey[800],
                            backgroundImage: NetworkImage(creatorAvatar),
                            onBackgroundImageError: (e, s) => {},
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Recorded by ', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                    Text(creatorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(creatorUsername, style: TextStyle(color: neonAccent.withValues(alpha: 0.8), fontSize: 11)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Text('Profile', style: TextStyle(color: neonAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios, color: neonAccent, size: 12),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetricColumn('Distance', '$distKm km'),
                      _buildMetricColumn('Elevation Gain', elevation),
                      _buildMetricColumn('Est. Time', 'Unknown'), // Can be calculated dynamically later
                    ],
                  ),
                  const SizedBox(height: 28),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildConditionItem(Icons.cloud_outlined, '16°C', 'Partly Cloudy'),
                        Container(width: 1, height: 40, color: Colors.white10),
                        _buildConditionItem(Icons.wb_twilight, '6:18 PM', 'Sunset'),
                        Container(width: 1, height: 40, color: Colors.white10),
                        _buildConditionItem(Icons.terrain, 'Rocky', 'Surface'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  const Row(
                    children: [
                      Icon(Icons.show_chart, color: neonAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Elevation Profile', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const InteractiveElevationScrubber(),
                  
                  const SizedBox(height: 32),

                  const Text('Points of Interest', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 130,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildWaypointCard(Icons.local_parking, 'Parking Lot A', '0.0 km'),
                        _buildWaypointCard(Icons.camera_alt_outlined, 'Eagle Rock', '4.2 km'),
                        _buildWaypointCard(Icons.water_drop_outlined, 'Fresh Spring', '8.7 km'),
                        _buildWaypointCard(Icons.flag_outlined, 'Summit', '9.2 km'),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: bgColor,
          border: const Border(top: BorderSide(color: Colors.white10)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => isDownloaded = !isDownloaded);
                },
                child: Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    color: isDownloaded ? neonAccent.withValues(alpha: 0.2) : cardSurface,
                    border: Border.all(color: isDownloaded ? neonAccent : Colors.white10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isDownloaded ? Icons.cloud_done : Icons.cloud_download_outlined, 
                    color: isDownloaded ? neonAccent : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: neonAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starting Live Navigation...')));
                    },
                    child: const Text('Start Navigation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildConditionItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: neonAccent, size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  Widget _buildWaypointCard(IconData icon, String title, String dist) {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: neonAccent, size: 16),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(dist, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}

class InteractiveElevationScrubber extends StatefulWidget {
  const InteractiveElevationScrubber({super.key});

  @override
  State<InteractiveElevationScrubber> createState() => _InteractiveElevationScrubberState();
}

class _InteractiveElevationScrubberState extends State<InteractiveElevationScrubber> {
  final List<double> normalizedData = [0.1, 0.15, 0.2, 0.35, 0.6, 0.8, 0.9, 1.0, 0.85, 0.6, 0.3, 0.1];
  final double minAltitude = 300.0;
  final double maxAltitude = 1120.0;
  double? scrubX;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: GestureDetector(
        onPanDown: (details) => setState(() => scrubX = details.localPosition.dx),
        onPanUpdate: (details) => setState(() => scrubX = details.localPosition.dx),
        onPanEnd: (details) => setState(() => scrubX = null),
        onPanCancel: () => setState(() => scrubX = null),
        child: Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 8.0, left: 16.0, right: 16.0),
          child: CustomPaint(
            painter: _ScrubberPainter(
              data: normalizedData,
              scrubX: scrubX,
              minAlt: minAltitude,
              maxAlt: maxAltitude,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  final List<double> data;
  final double? scrubX;
  final double minAlt;
  final double maxAlt;

  _ScrubberPainter({required this.data, this.scrubX, required this.minAlt, required this.maxAlt});

  @override
  void paint(Canvas canvas, Size size) {
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
      ..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, size.height), [neonAccent.withValues(alpha: 0.3), neonAccent.withValues(alpha: 0.0)]);
    canvas.drawPath(fillPath, paintFill);

    final paintStroke = Paint()..color = neonAccent..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke;
    canvas.drawPath(path, paintStroke);

    if (scrubX != null) {
      double clampedX = scrubX!.clamp(0.0, size.width);
      int index = (clampedX / stepX).round().clamp(0, data.length - 1);
      double actualX = index * stepX;
      double y = size.height - (data[index] * size.height);

      canvas.drawLine(Offset(actualX, 0), Offset(actualX, size.height), Paint()..color = Colors.white38..strokeWidth = 1);
      canvas.drawCircle(Offset(actualX, y), 6, Paint()..color = neonAccent);
      canvas.drawCircle(Offset(actualX, y), 3, Paint()..color = Colors.black);

      double realAltitude = minAlt + (data[index] * (maxAlt - minAlt));
      
      TextPainter tp = TextPainter(
        text: TextSpan(text: '${realAltitude.round()} m', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      
      double bgWidth = tp.width + 16;
      double bgHeight = tp.height + 8;
      double tipX = actualX - (bgWidth / 2);
      double tipY = y - bgHeight - 12;
      
      if (tipX < 0) tipX = 0;
      if (tipX + bgWidth > size.width) tipX = size.width - bgWidth;
      if (tipY < 0) tipY = y + 16;
      
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tipX, tipY, bgWidth, bgHeight), const Radius.circular(8)), Paint()..color = neonAccent);
      tp.paint(canvas, Offset(tipX + 8, tipY + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter oldDelegate) => oldDelegate.scrubX != scrubX;
}