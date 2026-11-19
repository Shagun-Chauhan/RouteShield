import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    try {
      await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Returns false if the notification could not be shown (permission denied etc.).
  Future<bool> show(int id, String title, String body) async {
    if (!_ready) return false;
    try {
      await _plugin.show(id, title, body,
          const NotificationDetails(android: AndroidNotificationDetails('routeshield_alerts', 'Journey alerts', importance: Importance.high, priority: Priority.high)));
      return true;
    } catch (_) {
      return false;
    }
  }
}
