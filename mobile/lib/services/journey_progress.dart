import 'dart:math';
import '../models/models.dart';
import 'deviation_detector.dart';

class JourneyProgress {
  final double remainingM;
  final double fraction; // 0..1 of the route completed
  final double alongM; // distance travelled along the route to the matched point
  final double offRouteM; // straight-line distance from the position to the route
  const JourneyProgress(this.remainingM, this.fraction, {this.alongM = 0, this.offRouteM = 0});
}

/// Where a position falls on a route.
class RouteMatch {
  final double alongM, offRouteM;
  final int segment; // index of the path segment (path[segment] -> path[segment + 1])
  const RouteMatch(this.alongM, this.offRouteM, this.segment);
}

/// Precomputed cumulative distances for a route polyline, so each GPS fix costs one pass
/// over a window of segments instead of rebuilding the whole route.
class RouteGeometry {
  final List<GeoPoint> path;
  final List<double> cum; // cum[i] = metres from path[0] to path[i]
  RouteGeometry._(this.path, this.cum);

  factory RouteGeometry(List<GeoPoint> path) {
    final cum = List<double>.filled(path.length, 0);
    for (var i = 1; i < path.length; i++) {
      cum[i] = cum[i - 1] + distanceMeters(path[i - 1], path[i]);
    }
    return RouteGeometry._(path, cum);
  }

  bool get isUsable => path.length >= 2 && totalM > 0;
  double get totalM => cum.isEmpty ? 0 : cum.last;

  ({double along, double off}) _project(GeoPoint p, int i) {
    final a = path[i], b = path[i + 1];
    final kx = cos(a.lat * pi / 180) * 111320.0, ky = 110540.0;
    final bx = (b.lng - a.lng) * kx, by = (b.lat - a.lat) * ky;
    final px = (p.lng - a.lng) * kx, py = (p.lat - a.lat) * ky;
    final len2 = bx * bx + by * by;
    final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
    final d = sqrt(pow(px - bx * t, 2) + pow(py - by * t, 2));
    return (along: cum[i] + (cum[i + 1] - cum[i]) * t, off: d);
  }

  RouteMatch? _scan(GeoPoint p, int from, int to) {
    RouteMatch? best;
    for (var i = max(0, from); i < min(to, path.length - 1); i++) {
      final r = _project(p, i);
      if (best == null || r.off < best.offRouteM) best = RouteMatch(r.along, r.off, i);
    }
    return best;
  }

  /// Nearest point on the route. Searches a window around [hintSegment] first so that routes
  /// which cross or double back on themselves do not snap to the wrong pass; falls back to a
  /// full scan when the windowed match is far from the route.
  RouteMatch? match(GeoPoint p, {int hintSegment = 0, double windowTrustM = 60, bool global = false}) {
    if (!isUsable) return null;
    if (global) return _scan(p, 0, path.length - 1);
    final near = _scan(p, hintSegment - 5, hintSegment + 300);
    if (near != null && near.offRouteM <= windowTrustM) return near;
    final all = _scan(p, 0, path.length - 1);
    if (all == null) return near;
    if (near != null && near.offRouteM <= all.offRouteM + 15) return near;
    return all;
  }
}

/// Distance still to travel ALONG the route from the point on the path nearest to [p].
JourneyProgress? journeyProgress(GeoPoint p, List<GeoPoint> path) {
  final g = RouteGeometry(path);
  final m = g.match(p);
  if (m == null) return null;
  final remaining = (g.totalM - m.alongM).clamp(0.0, g.totalM).toDouble();
  return JourneyProgress(remaining, (1 - remaining / g.totalM).clamp(0.0, 1.0).toDouble(), alongM: m.alongM, offRouteM: m.offRouteM);
}
