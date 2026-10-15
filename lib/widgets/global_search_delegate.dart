import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xplore_mobile/screens/trail_detail_screen.dart';
import 'package:xplore_mobile/screens/public_profile_screen.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class GlobalSearchDelegate extends SearchDelegate<String> {
  final Function(Map<String, dynamic>)? onSelectTrek;
  final String searchType; // 'public_trails', 'feed_trails', or 'athletes'

  GlobalSearchDelegate({this.onSelectTrek, required this.searchType});

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      appBarTheme: const AppBarTheme(backgroundColor: bgColor, elevation: 0),
      scaffoldBackgroundColor: bgColor,
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey)),
      textTheme: const TextTheme(titleLarge: TextStyle(color: Colors.white, fontSize: 18)),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: neonAccent),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => close(context, ''));

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.trim().isEmpty) {
      String hintText = searchType == 'athletes' 
          ? 'Search athletes by name or username...' 
          : 'Search trails by name or keywords...';
      return Center(child: Text(hintText, style: const TextStyle(color: Colors.grey)));
    }

    if (searchType == 'athletes') {
      return FutureBuilder<List<dynamic>>(
        future: Supabase.instance.client.from('profiles').select().or('display_name.ilike.%${query.trim()}%,username.ilike.%${query.trim()}%').limit(20),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: neonAccent));
          final results = snapshot.data ?? [];
          if (results.isEmpty) return const Center(child: Text('No athletes found.', style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final user = results[index];
              if (user['id'] == Supabase.instance.client.auth.currentUser?.id) return const SizedBox.shrink();
              return ListTile(
                leading: CircleAvatar(backgroundColor: neonAccent, backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null, child: user['avatar_url'] == null ? const Icon(Icons.person, color: Colors.black) : null),
                title: Text(user['display_name'] ?? 'Athlete', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(user['username'] != null ? '@${user['username']}' : '', style: const TextStyle(color: Colors.grey)),
                onTap: () { close(context, ''); Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: user['id']))); },
              );
            },
          );
        },
      );
    } else {
      String cleanQuery = query.trim().replaceAll('#', '');
      
      return FutureBuilder<List<dynamic>>(
        future: () async {
          var queryBuilder = Supabase.instance.client
              .from('completed_treks')
              .select()
              .or('trek_name.ilike.%$cleanQuery%,description.ilike.%$cleanQuery%');

          // If searching feed trails, limit results to YOU and YOUR FOLLOWS
          if (searchType == 'feed_trails') {
            final myId = Supabase.instance.client.auth.currentUser!.id;
            List<String> targetIds = [myId];
            final followsRes = await Supabase.instance.client.from('follows').select('following_id').eq('follower_id', myId);
            targetIds.addAll(followsRes.map((e) => e['following_id'].toString()));
            
            queryBuilder = queryBuilder.inFilter('user_id', targetIds);
          } else {
            // Otherwise it's public Explore search
            queryBuilder = queryBuilder.eq('is_public', true);
          }

          final res = await queryBuilder.limit(20);
          if (res.isEmpty) return [];

          final uids = res.map((e) => e['user_id']?.toString()).where((id) => id != null && id != 'null' && id.trim().isNotEmpty).toSet().toList();
          Map<String, dynamic> pMap = {};
          if (uids.isNotEmpty) {
            final profiles = await Supabase.instance.client.from('profiles').select('id, display_name, avatar_url').inFilter('id', uids);
            pMap = {for (var p in profiles) p['id'].toString(): p};
          }
          for (var t in res) {
            final p = pMap[t['user_id']?.toString()] ?? {};
            t['creator_name'] = p['display_name'] ?? 'Athlete';
            t['creator_avatar'] = p['avatar_url'];
          }
          return res;
        }(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: neonAccent));
          final results = snapshot.data ?? [];
          if (results.isEmpty) return const Center(child: Text('No trails found. Try another keyword!', style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final t = results[index];
              // Safety check just in case
              if (searchType == 'public_trails' && t['is_public'] == false) return const SizedBox.shrink(); 
              
              final distKm = (double.tryParse(t['distance']?.toString() ?? '0') ?? 0.0);
              final Map<String, dynamic> mappedTrek = {
                ...Map<String, dynamic>.from(t),
                'name': t['trek_name'],
                'distance_meters': distKm * 1000,
                'elevation_gain': double.tryParse(t['elevation_gain']?.toString() ?? '0') ?? 0,
                'route_geom': t['recorded_route'],
                'creator_id': t['user_id'],
                'creator_name': t['creator_name'],
                'creator_avatar': t['creator_avatar']
              };

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(width: 60, height: 60, decoration: BoxDecoration(color: cardSurface, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.terrain, color: neonAccent)),
                title: Text(mappedTrek['name'] ?? 'Trek', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('${distKm.toStringAsFixed(1)} km • Mapped by ${mappedTrek['creator_name']}', style: const TextStyle(color: neonAccent)),
                onTap: () { 
                  close(context, ''); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TrailDetailScreen(trek: mappedTrek, onStartTrail: () {
                    if (onSelectTrek != null) onSelectTrek!(mappedTrek);
                  }))); 
                },
              );
            },
          );
        },
      );
    }
  }
}