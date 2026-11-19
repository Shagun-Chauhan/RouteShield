import '../models/models.dart';

class AppConfig {
  /// Override at build time: flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000/api
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000/api');
  static const defaultCenter = GeoPoint(18.5204, 73.8567); // Pune, used only when GPS is unavailable
  static const lowBatteryThreshold = 15;
}
