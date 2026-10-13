import 'dart:async';
import 'dart:ui';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

const notificationChannelId = 'trek_tracking_channel';
const notificationId = 888;

Future<void> initializeTrackingService() async {
  final service = FlutterBackgroundService();

  // Only init UI-side notifications here
  if (Platform.isAndroid) {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Live Trek Tracking',
      description: 'Keeps the GPS and timer running in the background.',
      importance: Importance.low, 
    );
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
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ---------------------------------------------------------------------------
// THE REAL BACKGROUND LOOP (CRASH FIXED)
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized(); // CRITICAL for isolate stability

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  int elapsedSeconds = 0;

  // The core GPS tracking loop
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    elapsedSeconds += 2;
    
    int hours = elapsedSeconds ~/ 3600;
    int minutes = (elapsedSeconds % 3600) ~/ 60;
    int seconds = elapsedSeconds % 60;
    String timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        try {
          Position pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
          );
          
          double speedKmh = pos.speed * 3.6;

          // PERFECT FIX: Use the built-in isolate-safe notification updater!
          service.setForegroundNotificationInfo(
            title: 'Live Trek Tracking',
            content: 'Time: $timeStr  •  Speed: ${speedKmh.toStringAsFixed(1)} km/h',
          );
          
          // Broadcast live data to the UI HUD
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