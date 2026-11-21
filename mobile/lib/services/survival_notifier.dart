import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SurvivalNotifier {
  SurvivalNotifier._();
  static final instance = SurvivalNotifier._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Pass requestPermission: true only from the UI isolate (Android 13+ prompt).
  Future<void> init({bool requestPermission = false}) async {
    if (!_ready) {
      await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
    }
    if (requestPermission) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> show(int id, String title, String body) async {
    try {
      await init();
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'routeshield_battery',
            'Battery and safety alerts',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (_) {/* notifications blocked by the user */}
  }
}
