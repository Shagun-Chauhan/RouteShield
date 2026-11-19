import 'dart:math';
import '../models/models.dart';

double _rad(double d) => d * pi / 180;

double distanceMeters(GeoPoint a, GeoPoint b) {
  const r = 6371000.0;
  final dLat = _rad(b.lat - a.lat), dLng = _rad(b.lng - a.lng);
  final h = pow(sin(dLat / 2), 2) + cos(_rad(a.lat)) * cos(_rad(b.lat)) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(sqrt(h));
}

/// Shortest distance from point [p] to the polyline [path], in metres.
double distanceToPathMeters(GeoPoint p, List<GeoPoint> path) {
  if (path.isEmpty) return double.infinity;
  if (path.length == 1) return distanceMeters(p, path.first);
  double best = double.infinity;
  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i], b = path[i + 1];
    final kx = cos(_rad(a.lat)) * 111320.0, ky = 110540.0;
    final bx = (b.lng - a.lng) * kx, by = (b.lat - a.lat) * ky;
    final px = (p.lng - a.lng) * kx, py = (p.lat - a.lat) * ky;
    final len2 = bx * bx + by * by;
    final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
    final dx = px - bx * t, dy = py - by * t;
    best = min(best, sqrt(dx * dx + dy * dy));
  }
  return best;
}

/// Flags a deviation only after several consecutive, reasonably accurate fixes
/// are far from the route. This avoids false alarms from single GPS-drift readings.
class DeviationDetector {
  final double thresholdM;
  final int requiredConsecutive;
  final double maxAccuracyM;
  int _count = 0;
  DeviationDetector({this.thresholdM = 120, this.requiredConsecutive = 3, this.maxAccuracyM = 50});

  bool update(GeoPoint p, double accuracyM, List<GeoPoint> path) {
    if (accuracyM > maxAccuracyM) return _count >= requiredConsecutive; // ignore poor fixes
    if (distanceToPathMeters(p, path) > thresholdM) {
      _count++;
    } else {
      _count = 0;
    }
    return _count >= requiredConsecutive;
  }

  void reset() => _count = 0;
}
