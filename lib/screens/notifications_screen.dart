import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color neonAccent = Color(0xFFD4FF00);
const Color cardSurface = Color(0xFF161922);
const Color bgColor = Color(0xFF0F1115);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  RealtimeChannel? _notificationChannel;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _setupRealtime();
  }

  // Listens to the database and instantly refreshes if a new notification arrives
  void _setupRealtime() {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    _notificationChannel = Supabase.instance.client
        .channel('public:user_notifications')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              _fetchNotifications();
            })
        .subscribe();
  }

  @override
  void dispose() {
    _notificationChannel?.unsubscribe(); // Clean up the listener when closed
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final response = await Supabase.instance.client
          .from('user_notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      setState(() {
        _notifications = response;
      });

      // Mark all as read when opened
      await Supabase.instance.client
          .from('user_notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

    } catch (e) {
      debugPrint("Error fetching notifications: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await Supabase.instance.client.from('user_notifications').delete().eq('id', id);
      setState(() {
        _notifications.removeWhere((n) => n['id'] == id);
      });
    } catch (e) {
      debugPrint("Error deleting notification: $e");
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'follow': return Icons.person_add;
      case 'kudos': return Icons.directions_run;
      case 'map': return Icons.map;
      default: return Icons.notifications;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'follow': return Colors.blueAccent;
      case 'kudos': return Colors.orangeAccent;
      case 'map': return neonAccent;
      default: return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: neonAccent))
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: Colors.black,
                  backgroundColor: neonAccent,
                  onRefresh: _fetchNotifications,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 24),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      final isRead = n['is_read'] ?? true;
                      final type = n['icon_type'] ?? 'system';
                      
                      return Dismissible(
                        key: Key(n['id'].toString()),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) => _deleteNotification(n['id']),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: _getColorForType(type).withOpacity(0.15), shape: BoxShape.circle),
                              child: Icon(_getIconForType(type), color: _getColorForType(type), size: 20),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n['title'] ?? '', style: TextStyle(color: isRead ? Colors.white70 : Colors.white, fontSize: 15, fontWeight: isRead ? FontWeight.normal : FontWeight.bold, height: 1.3)),
                                  const SizedBox(height: 4),
                                  Text(n['message'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
                                ],
                              ),
                            ),
                            if (!isRead)
                              Container(
                                margin: const EdgeInsets.only(top: 8, left: 8),
                                width: 8, height: 8,
                                decoration: const BoxDecoration(color: neonAccent, shape: BoxShape.circle),
                              )
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 80, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text("You're all caught up!", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("No new notifications right now.", style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}