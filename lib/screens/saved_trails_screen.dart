import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xplore_mobile/screens/trail_detail_screen.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class SavedTrailsScreen extends StatefulWidget {
  const SavedTrailsScreen({super.key});

  @override
  State<SavedTrailsScreen> createState() => _SavedTrailsScreenState();
}

class _SavedTrailsScreenState extends State<SavedTrailsScreen> {
  bool _isLoading = true;
  List<dynamic> _savedTreks = [];

  @override
  void initState() {
    super.initState();
    _fetchSavedTreks();
  }

  Future<void> _fetchSavedTreks() async {
    setState(() => _isLoading = true);
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;

    try {
      // UPDATED: Added explicitly request '*, ' before public_treks(*) 
      // This forces Supabase to return the parent row and structure the JSON properly.
      final response = await Supabase.instance.client
          .from('saved_treks')
          .select('*, public_treks(*)') 
          .eq('user_id', myId)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          // Extract the joined public_treks object
          _savedTreks = response.map((item) => item['public_treks']).where((t) => t != null).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load saved trails: $e'), backgroundColor: Colors.redAccent));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Saved Trails', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: neonAccent))
        : _savedTreks.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmark_border, size: 54, color: Colors.white24),
                    const SizedBox(height: 16),
                    const Text('No saved trails yet.', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Tap the bookmark icon on any trail to save it here.', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              )
            : RefreshIndicator(
                color: neonAccent,
                backgroundColor: cardSurface,
                onRefresh: _fetchSavedTreks,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _savedTreks.length,
                  itemBuilder: (context, index) {
                    final trek = _savedTreks[index];
                    final imageUrl = trek['image_url'] ?? 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?q=80&w=600&auto=format&fit=crop';
                    final distKm = ((trek['distance_meters'] ?? 0) / 1000).toStringAsFixed(1);
                    final elevM = (trek['elevation_gain'] ?? 0).toStringAsFixed(0);
                    final difficulty = trek['difficulty'] ?? 'Moderate';
                    
                    Color badgeColor = difficulty == 'Hard' ? Colors.red : (difficulty == 'Easy' ? Colors.green : Colors.orange);

                    return GestureDetector(
                      onTap: () async {
                        // Open the trail, and refresh the list when we return in case they unsaved it!
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => TrailDetailScreen(trek: trek, onStartTrail: () => Navigator.pop(context))));
                        _fetchSavedTreks();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(imageUrl, width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(width: 80, height: 80, color: bgColor, child: const Icon(Icons.terrain, color: Colors.white24))),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(trek['name'] ?? 'Trek', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.straighten, color: neonAccent, size: 14), const SizedBox(width: 4), Text('$distKm km', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.trending_up, color: neonAccent, size: 14), const SizedBox(width: 4), Text('${elevM}m', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text(difficulty, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16)
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
    );
  }
}