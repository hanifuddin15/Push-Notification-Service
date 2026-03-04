import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:guard_monitoring_app/app/core/models/api_response.dart';
import 'package:guard_monitoring_app/app/core/models/user.dart';
import 'package:guard_monitoring_app/app/core/services/api_service.dart';
import 'package:guard_monitoring_app/app/repository/auth_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:guard_monitoring_app/app/core/error/failure.dart';

class PushNotificationService {
  PushNotificationService._internal();

  static final PushNotificationService instance =
      PushNotificationService._internal();

  factory PushNotificationService() => instance;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final ApiService _apiService = ApiService.instance;

  Future<void> initialize() async {
    // 1. Request permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
      'Notification permission status: ${settings.authorizationStatus}',
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('User granted notification permission');

      // 2. On iOS, set foreground notification presentation options
      if (Platform.isIOS) {
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // 3. Get FCM Token & Send to Backend
      await uploadFcmToken();

      // 4. Listen to token refreshes
      _fcm.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM token refreshed: $newToken');
        await uploadFcmToken(forcedToken: newToken);
      });

      // 5. Listen to Foreground Messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          '🔔 Foreground message received: ${message.notification?.title}',
        );
        debugPrint('Message data: ${message.data}');
      });

      // 6. Handle notification open when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
          '🔔 Notification tapped (background): ${message.notification?.title}',
        );
      });

      // 7. Check if app was opened from a terminated state via notification
      RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '🔔 App opened from terminated state via notification: ${initialMessage.notification?.title}',
        );
      }
    } else {
      debugPrint(
        'User declined notification permission: ${settings.authorizationStatus}',
      );
    }
  }

  Future<void> uploadFcmToken({String? forcedToken}) async {
    try {
      // Get the current user
      UserModel? currentUser = AuthRepository.instance.getUserData();
      if (currentUser == null) {
        debugPrint('FCM: User not logged in, skipping token upload');
        return;
      }

      // Retrieve Firebase Token
      String? fcmToken = forcedToken;
      if (fcmToken == null) {
        if (Platform.isIOS) {
          String? apnsToken;
          for (int i = 0; i < 5; i++) {
            apnsToken = await _fcm.getAPNSToken();
            if (apnsToken != null) break;
            debugPrint(
              'APNS token not ready, retrying in 2s... (attempt ${i + 1}/5)',
            );
            await Future<void>.delayed(const Duration(seconds: 2));
          }

          if (apnsToken != null) {
            debugPrint('APNS token: $apnsToken');
            fcmToken = await _fcm.getToken();
          } else {
            debugPrint('❌ Failed to get APNS token after retries');
            return;
          }
        } else {
          fcmToken = await _fcm.getToken();
        }
      }

      if (fcmToken == null) {
        debugPrint('❌ FCM token is null, skipping upload');
        return;
      }

      debugPrint('FCM Token: $fcmToken');

      // Get Device ID
      String deviceId = "Unknown";
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? "Unknown_iOS_Device";
      }

      // Determine Platform
      String platform = Platform.isIOS ? 'ios' : 'android';

      // Call Backend API
      final result = await saveUserToken(
        userId: currentUser.userId ?? '',
        fcmToken: fcmToken,
        deviceId: deviceId,
        platform: platform,
      );

      result.fold(
        (failure) => debugPrint('❌ FCM Token Save Failed: ${failure.message}'),
        (success) => debugPrint('✅ FCM Token Saved Successfully!'),
      );
    } catch (e) {
      debugPrint('Error in FCM token upload: $e');
    }
  }

  Future<Either<Failure, ApiResponse>> saveUserToken({
    required String userId,
    required String fcmToken,
    required String deviceId,
    required String platform,
  }) async {
    final ApiResponse response = await _apiService.doPostRequest(
      apiEndPoint: 'firebase_notification/save-user-token',
      requestData: {
        'user_id': userId,
        'fcm_token': fcmToken,
        'device_id': deviceId,
        'platform': platform,
      },
      isFormData: false,
      responseDataKey: 'data',
      showSuccessMessage: false,
      addUserData: false,
      enableLoading: false,
    );

    try {
      if (response.isSuccessful) {
        return Right(response);
      } else {
        return Left(Failure(message: 'Failed to save FCM token'));
      }
    } catch (e) {
      return Left(Failure(message: e.toString()));
    }
  }
}
