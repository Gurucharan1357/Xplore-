import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xplore_mobile/screens/trail_detail_screen.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userProfile;
  List<dynamic> _userTreks = [];
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _fetchPublicProfileData();
  }

  Future<void> _fetchPublicProfileData() async {
    setState(() => _isLoading = true);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    try {
      final profileResponse = await Supabase.instance.client.from('profiles').select().eq('id', widget.userId).maybeSingle();
      final followers = await Supabase.instance.client.from('follows').select('follower_id').eq('following_id', widget.userId);
      final following = await Supabase.instance.client.from('follows').select('following_id').eq('follower_id', widget.userId);
      
      if (currentUserId != null) {
        _isFollowing = followers.any((f) => f['follower_id'] == currentUserId);
      }

      final trekData = await Supabase.instance.client.from('public_treks').select().eq('creator_id', widget.userId).order('created_at', ascending: false);
          
      if (mounted) {
        setState(() {
          _userProfile = profileResponse;
          _followersCount = followers.length;
          _followingCount = following.length;
          _userTreks = trekData;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId == widget.userId) return;

    setState(() {
      _isFollowing = !_isFollowing;
      _followersCount += _isFollowing ? 1 : -1;
    });

    try {
      if (_isFollowing) {
        await Supabase.instance.client.from('follows').insert({'follower_id': currentUserId, 'following_id': widget.userId});
      } else {
        await Supabase.instance.client.from('follows').delete().eq('follower_id', currentUserId).eq('following_id', widget.userId);
      }
    } catch (_) {
      setState(() {
        _isFollowing = !_isFollowing;
        _followersCount += _isFollowing ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: bgColor, body: Center(child: CircularProgressIndicator(color: neonAccent)));
    }

    final displayName = _userProfile?['display_name'] ?? 'Athlete';
    final username = '@${_userProfile?['username'] ?? 'explorer'}';
    final avatarUrl = _userProfile?['avatar_url'] ?? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=500&auto=format&fit=crop';
    final isMe = Supabase.instance.client.auth.currentUser?.id == widget.userId;

    final totalDistanceKm = _userTreks.fold<double>(0.0, (acc, item) => acc + ((item['distance_meters'] ?? 0) as num)) / 1000;
    final totalElevationM = _userTreks.fold<double>(0.0, (acc, item) => acc + ((item['elevation_gain'] ?? 0) as num));

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: RefreshIndicator(
        color: neonAccent, backgroundColor: cardSurface,
        onRefresh: _fetchPublicProfileData,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: neonAccent, width: 2)), 
                    child: CircleAvatar(radius: 46, backgroundColor: Colors.grey[800], backgroundImage: NetworkImage(avatarUrl), onBackgroundImageError: (e, s) => {})
                  ),
                  const SizedBox(height: 16),
                  Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(username, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 16),
                  
                  if (!isMe)
                    SizedBox(
                      width: 140, height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isFollowing ? Colors.transparent : neonAccent,
                          foregroundColor: _isFollowing ? Colors.white : Colors.black,
                          side: BorderSide(color: _isFollowing ? Colors.white54 : neonAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                        ),
                        onPressed: _toggleFollow,
                        child: Text(_isFollowing ? 'Following' : 'Follow', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    )
                ],
              ),
            ),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(24)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildHeroStat('Total Dist', totalDistanceKm.toStringAsFixed(1), 'km'),
                  _buildHeroStat('Total Elev', totalElevationM.toStringAsFixed(0), 'm'),
                  _buildHeroStat('Treks', '${_userTreks.length}', ''),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _buildCommunityPill('$_followersCount', 'Followers')),
                const SizedBox(width: 16),
                Expanded(child: _buildCommunityPill('$_followingCount', 'Following')),
              ],
            ),
            const SizedBox(height: 32),

            Text("$displayName's Trails", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            
            _userTreks.isEmpty 
              ? _buildEmptyTrailsState(displayName) 
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _userTreks.length,
                  itemBuilder: (context, index) {
                    return _buildPublicTrailCard(_userTreks[index]);
                  },
                )
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStat(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), if (unit.isNotEmpty) Text(' $unit', style: const TextStyle(color: Colors.grey, fontSize: 12))],
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

  Widget _buildEmptyTrailsState(String name) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10, width: 1.5)),
      child: Column(
        children: [
          const Icon(Icons.landscape, size: 40, color: Colors.white24),
          const SizedBox(height: 16),
          Text("$name hasn't published any trails yet.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPublicTrailCard(Map<String, dynamic> trek) {
    final distKm = ((trek['distance_meters'] ?? 0) / 1000).toStringAsFixed(1);
    final elevM = (trek['elevation_gain'] ?? 0).toStringAsFixed(0);
    final difficulty = trek['difficulty'] ?? 'Moderate';
    Color badgeColor = difficulty == 'Hard' ? Colors.red : (difficulty == 'Easy' ? Colors.green : Colors.orange);
    
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => TrailDetailScreen(trek: trek, onStartTrail: () { Navigator.pop(context); })));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(trek['name'] ?? 'Wilderness Trek', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text(difficulty, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.straighten, color: neonAccent, size: 16), const SizedBox(width: 4), Text('$distKm km', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(width: 16),
                const Icon(Icons.trending_up, color: neonAccent, size: 16), const SizedBox(width: 4), Text('${elevM}m', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}