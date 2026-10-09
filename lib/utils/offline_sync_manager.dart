import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OfflineSyncManager {
  static const String _pendingKey = 'pending_treks';
  static const String _recoveryKey = 'active_trek_recovery';

  // --- 1. FAILED UPLOAD CACHE ---
  static Future<void> savePending(String type, Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> existing = prefs.getStringList(_pendingKey) ?? [];
    existing.add(jsonEncode(payload));
    await prefs.setStringList(_pendingKey, existing);
  }

  static Future<List<Map<String, dynamic>>> getPendingTreks() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> existing = prefs.getStringList(_pendingKey) ?? [];
    return existing.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<int> syncPending() async {
    final pending = await getPendingTreks();
    if (pending.isEmpty) return 0;

    int successCount = 0;
    final prefs = await SharedPreferences.getInstance();
    List<String> remaining = [];

    for (var trek in pending) {
      try {
        await Supabase.instance.client.from('public_treks').insert(trek);
        successCount++;
      } catch (e) {
        debugPrint('Sync failed for a trek, keeping in cache: $e');
        remaining.add(jsonEncode(trek)); 
      }
    }
    
    await prefs.setStringList(_pendingKey, remaining);
    return successCount; // Returns how many successfully uploaded
  }

  // --- 2. CRASH / ACCIDENTAL CLOSE RECOVERY ---
  // Call this every few seconds during tracking
  static Future<void> autoSaveLiveTrek(List<dynamic> rawTrekData) async {
    final prefs = await SharedPreferences.getInstance();
    // Convert GPS points to simple maps to store locally
    final simplified = rawTrekData.map((p) => {
      'lat': p.latitude, 'lng': p.longitude, 'alt': p.altitude, 'speed': p.speed
    }).toList();
    await prefs.setString(_recoveryKey, jsonEncode(simplified));
  }

  static Future<bool> hasUnfinishedTrek() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_recoveryKey);
  }

  static Future<void> clearUnfinishedTrek() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recoveryKey);
  }
}