import 'dart:async';
import 'dart:ui';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Notification Channel IDs
const notificationChannelId = 'trek_tracking_channel';
const notificationId = 888;

Future<void> initializeTrackingService() async {
  final service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Create Android Notification Channel
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId,
    'Live Trek Tracking',
    description: 'Keeps the GPS and timer running in the background.',
    importance: Importance.low, // Low importance prevents constant ringing
  );

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Xplore Navigation',
      initialNotificationContent: 'Warming up GPS...',
      foregroundServiceNotificationId: notificationId,
      // Removed foregroundServiceType for compatibility with your package version
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

// iOS specific background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ---------------------------------------------------------------------------
// THE REAL BACKGROUND LOOP 
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Handle Android specific background toggles
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // Allow UI to stop the service
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Re-initialize Supabase for the background isolate so syncing doesn't crash
  try {
    await Supabase.initialize(
      url: 'https://lvkgxsfsvsydfuywphiv.supabase.co',
      anonKey: 'sb_publishable_549oaEIaBH2n8TzYaeQbLw_8kMM9Wzb',
    );
  } catch (e) {
    // Already initialized
  }

  int elapsedSeconds = 0;

  // The core GPS tracking loop (Runs every 2 seconds)
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    elapsedSeconds += 2;
    
    // Formatting time for the notification
    int hours = elapsedSeconds ~/ 3600;
    int minutes = (elapsedSeconds % 3600) ~/ 60;
    int seconds = elapsedSeconds % 60;
    String timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        try {
          // REAL GPS FETCHING
          Position pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
          );
          
          double speedKmh = pos.speed * 3.6;

          // Update the persistent notification with real live stats
          flutterLocalNotificationsPlugin.show(
            notificationId,
            'Live Trek Tracking',
            'Time: $timeStr  •  Speed: ${speedKmh.toStringAsFixed(1)} km/h',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                notificationChannelId,
                'Live Trek Tracking',
                icon: 'ic_bg_service_small', 
                ongoing: true, 
                onlyAlertOnce: true, 
              ),
            ),
          );
          
          // Stream coordinates back to the UI
          service.invoke(
            'update',
            {
              "lat": pos.latitude,
              "lng": pos.longitude,
              "speed": pos.speed,
              "altitude": pos.altitude,
            },
          );
        } catch (e) {
          // Temporarily lost GPS signal, ignore and try again next loop
        }
      }
    }
  });
}