import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const int _downloadNotificationId = 1001;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  Future<void> showDownloadProgress({
    required String title,
    required String body,
    required int progress,
    int maxProgress = 100,
  }) async {
    if (!_initialized) return;
    final androidDetails = AndroidNotificationDetails(
      'offline_download_channel',
      'Download mappe offline',
      channelDescription: 'Stato download delle mappe per uso offline',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: true,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      category: AndroidNotificationCategory.progress,
    );

    const iosDetails = DarwinNotificationDetails(presentAlert: false, presentBadge: false, presentSound: false);

    await _plugin.show(
      _downloadNotificationId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> cancelDownloadNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(_downloadNotificationId);
  }
}
