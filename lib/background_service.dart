
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import 'firebase_options.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      foregroundServiceTypes: [
        AndroidForegroundType.location,
      ],
      foregroundServiceNotificationId: 888,
      initialNotificationTitle: 'UsOnMap',
      initialNotificationContent: 'Live location sharing is active',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

Future<void> startLocationService() async {
  final service = FlutterBackgroundService();

  if (!await service.isRunning()) {
    await service.startService();
  }
}

Future<void> stopLocationService() async {
  final service = FlutterBackgroundService();

  service.invoke('stopService');
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  StreamSubscription<Position>? positionSubscription;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (service is AndroidServiceInstance) {
      await service.setAsForegroundService();

      await service.setForegroundNotificationInfo(
        title: 'UsOnMap',
        content: 'Sharing live location',
      );
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      service.invoke('serviceError', {
        'message': 'User is not logged in',
      });
      service.stopSelf();
      return;
    }

    final uid = user.uid;

    const partnerChatId = 'private_chat';

    final locationRef = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(partnerChatId)
        .collection('live_locations')
        .doc(uid);

    double lastBearing = 0;

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 10),
    );

    positionSubscription =
        Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (Position position) async {
        try {
          if (position.speed > 0.8 &&
              position.heading.isFinite &&
              position.heading >= 0 &&
              position.heading < 360) {
            lastBearing = position.heading;
          }

          await locationRef.set({
            'uid': uid,
            'sharingEnabled': true,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'bearing': lastBearing,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          service.invoke('locationUpdate', {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'bearing': lastBearing,
          });
        } catch (e) {
          service.invoke('serviceError', {
            'message': e.toString(),
          });
        }
      },
      onError: (error) {
        service.invoke('serviceError', {
          'message': error.toString(),
        });
      },
    );

    service.on('stopService').listen((event) async {
      await positionSubscription?.cancel();

      try {
        await locationRef.set({
          'uid': uid,
          'sharingEnabled': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      service.stopSelf();
    });
  } catch (e) {
    service.invoke('serviceError', {
      'message': e.toString(),
    });
    await positionSubscription?.cancel();
    service.stopSelf();
  }
}
