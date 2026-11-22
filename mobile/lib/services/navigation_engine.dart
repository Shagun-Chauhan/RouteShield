import 'dart:math';
import '../core/nav_config.dart';
import '../models/models.dart';
import 'journey_progress.dart';

class StepInfo {
  final RouteStep step;
  final double distanceM; // from the user to the manoeuvre, along the route
  const StepInfo(this.step, this.distanceM);
}

class UpcomingRisk {
  final SegmentAssessment segment;
  final double distanceM; // 0 when the user is already inside it
  final bool inside;
  const UpcomingRisk(this.segment, this.distanceM, this.inside);
}

/// Pure route-following maths for one selected route. No I/O, no Flutter: unit-testable.
class NavigationEngine {
  NavigationEngine(this.route) : geometry = RouteGeometry(route.path) {
    if (!geometry.isUsable) return;
    final located = <(double, RouteStep)>[];
    for (final s in route.steps) {
      double? along;
      final idx = s.pathIndex;
      if (idx != null && idx >= 0 && idx < geometry.cum.length) {
        along = geometry.cum[idx];
      } else if (s.location != null) {
        along = geometry.match(s.location!, global: true)?.alongM;
      }
      if (along != null) located.add((along, s));
    }
    located.sort((a, b) => a.$1.compareTo(b.$1));
    _steps = located;
  }

  final RouteOption route;
  final RouteGeometry geometry;
  List<(double, RouteStep)> _steps = const [];

  bool get usable => geometry.isUsable;
  bool get hasSteps => _steps.isNotEmpty;

  /// Next manoeuvre ahead of [alongM], or null when the server supplied no usable steps.
  StepInfo? nextStep(double alongM) {
    for (final (a, s) in _steps) {
      if (a > alongM + NavConfig.stepAdvanceM) return StepInfo(s, a - alongM);
    }
    return null;
  }

  /// First high-risk (preferred) or insufficient-data segment still ahead, within a useful horizon.
  UpcomingRisk? upcomingRisk(double alongM, {double horizonM = 1500}) {
    UpcomingRisk? unknown;
    for (final seg in route.segments) {
      final a = seg.startIndex, b = seg.endIndex;
      if (a == null || b == null || a < 0 || b >= geometry.cum.length || b <= a) continue;
      final start = geometry.cum[a], end = geometry.cum[b];
      if (end <= alongM) continue; // already passed
      final dist = max(0.0, start - alongM);
      if (dist > horizonM) break;
      final inside = start <= alongM;
      if (seg.riskLevel == 'high') return UpcomingRisk(seg, dist, inside);
      if (seg.riskLevel == 'unknown') unknown ??= UpcomingRisk(seg, dist, inside);
    }
    return unknown;
  }

  /// Planned pace (m/s) from the routing provider's own duration. null when it has none.
  double? get plannedMps => route.durationMin > 0 && route.distanceKm > 0 ? route.distanceKm * 1000 / (route.durationMin * 60) : null;

  /// Remaining time from the planned pace, nudged by the user's recent moving speed.
  /// This is NOT a live-traffic estimate; the UI labels it accordingly.
  ({Duration remaining, String basis})? eta(double remainingM, double avgMovingMps) {
    final planned = plannedMps;
    if (planned == null) {
      if (avgMovingMps < 0.8) return null;
      return (remaining: Duration(seconds: (remainingM / avgMovingMps).round()), basis: 'your recent speed');
    }
    if (avgMovingMps < 0.8) return (remaining: Duration(seconds: (remainingM / planned).round()), basis: 'planned pace');
    final blended = (0.6 * avgMovingMps + 0.4 * planned).clamp(planned * 0.5, planned * 1.5).toDouble();
    return (remaining: Duration(seconds: (remainingM / blended).round()), basis: 'your speed and planned pace');
  }
}
