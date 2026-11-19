import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class StoredLocation {
  final GeoPoint point;
  final DateTime at;
  const StoredLocation(this.point, this.at);
}

class LocationService {
  static Future<bool> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  static Future<GeoPoint?> current() async {
    try {
      if (!await ensurePermission()) return null;
final p = await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.high,
  timeLimit: const Duration(seconds: 10),
);      return GeoPoint(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// In battery-saver mode: lower accuracy and a larger distance filter => fewer updates.
  static Stream<Position> stream({bool saver = false}) => Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: saver ? LocationAccuracy.low : LocationAccuracy.high, distanceFilter: saver ? 100 : 15));

  static Future<void> save(SharedPreferences p, GeoPoint g) async {
    await p.setDouble('last_lat', g.lat);
    await p.setDouble('last_lng', g.lng);
    await p.setString('last_at', DateTime.now().toIso8601String());
  }

  static StoredLocation? load(SharedPreferences p) {
    final lat = p.getDouble('last_lat'), lng = p.getDouble('last_lng'), at = DateTime.tryParse(p.getString('last_at') ?? '');
    if (lat == null || lng == null || at == null) return null;
    return StoredLocation(GeoPoint(lat, lng), at);
  }
}
