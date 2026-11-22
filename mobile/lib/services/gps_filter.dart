import 'dart:math';
import '../core/nav_config.dart';
import '../models/models.dart';
import 'deviation_detector.dart';

enum FixVerdict { accepted, rejectedAccuracy, rejectedJump }

/// A position that passed the filter, with smoothed speed/heading.
class FilteredFix {
  final GeoPoint point;
  final double accuracyM;
  final double speedMps; // smoothed, >= 0; 0 when stationary
  final double? headingDeg; // null when not moving or unknown
  final DateTime at;
  const FilteredFix(this.point, this.accuracyM, this.speedMps, this.headingDeg, this.at);
}

class FilterResult {
  final FixVerdict verdict;
  final FilteredFix? fix; // set when accepted
  const FilterResult(this.verdict, [this.fix]);
}

/// Pure GPS-noise filter (no I/O, unit-testable).
///  * drops fixes with poor reported accuracy;
///  * drops physically impossible jumps (implied speed above [maxSpeedMps]);
///  * suppresses marker jitter while stationary (movement below the noise floor keeps the
///    previous point and adds no distance);
///  * derives a smoothed speed and a heading that is only reported while moving.
class GpsFilter {
  GpsFilter({
    this.maxAccuracyM = NavConfig.maxAccuracyM,
    this.maxSpeedMps = NavConfig.maxPlausibleSpeedMps,
    this.noiseFloorM = NavConfig.noiseFloorM,
  });
  final double maxAccuracyM, maxSpeedMps, noiseFloorM;

  GeoPoint? _last;
  DateTime? _lastAt;
  double _speed = 0;
  double? _heading;
  double _travelled = 0;
  int _jumpStreak = 0;

  double get distanceTravelledM => _travelled;
  /// Smoothed speed across moving samples only; used for ETA, not shown as "current speed".
  double _avgMoving = 0;
  double get averageMovingSpeedMps => _avgMoving;

  void reset() {
    _last = null;
    _lastAt = null;
    _speed = 0;
    _heading = null;
    _travelled = 0;
    _avgMoving = 0;
    _jumpStreak = 0;
  }

  static double bearing(GeoPoint a, GeoPoint b) {
    final dLng = (b.lng - a.lng) * pi / 180;
    final la = a.lat * pi / 180, lb = b.lat * pi / 180;
    final y = sin(dLng) * cos(lb);
    final x = cos(la) * sin(lb) - sin(la) * cos(lb) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// [deviceSpeedMps] / [deviceHeadingDeg] are the platform's own values (negative = unknown).
  FilterResult update(GeoPoint p, double accuracyM, DateTime at, {double deviceSpeedMps = -1, double deviceHeadingDeg = -1}) {
    if (accuracyM.isNaN || accuracyM <= 0 || accuracyM > maxAccuracyM) {
      return const FilterResult(FixVerdict.rejectedAccuracy);
    }
    final last = _last, lastAt = _lastAt;
    if (last == null || lastAt == null) {
      _last = p;
      _lastAt = at;
      return FilterResult(FixVerdict.accepted, FilteredFix(p, accuracyM, 0, null, at));
    }

    final dt = max(0.001, at.difference(lastAt).inMilliseconds / 1000.0);
    final d = distanceMeters(last, p);
    // Impossible jump: ignore, but accept after 3 in a row (the device really did relocate).
    if (d / dt > maxSpeedMps && d > 100 && _jumpStreak < 2) {
      _jumpStreak++;
      return const FilterResult(FixVerdict.rejectedJump);
    }
    _jumpStreak = 0;

    final stationary = d < max(noiseFloorM, accuracyM * 0.5) && deviceSpeedMps < 0.8;
    if (stationary) {
      // Keep the previous point AND its timestamp: slow walkers accumulate distance against the
      // last accepted point, so speed stays correct once the noise floor is crossed.
      if (dt > 10 || (deviceSpeedMps >= 0 && deviceSpeedMps < 0.5)) {
        _speed = dt > 10 ? 0 : _speed * 0.5;
        if (_speed < 0.3) _speed = 0;
      }
      // The marker must not wander while standing still.
      return FilterResult(FixVerdict.accepted, FilteredFix(last, accuracyM, _speed, _heading, at));
    }

    _travelled += d;
    final instant = deviceSpeedMps >= 0 && deviceSpeedMps <= maxSpeedMps ? deviceSpeedMps : d / dt;
    _speed = _speed == 0 ? instant : _speed * 0.6 + instant * 0.4;
    if (_speed > 0.8) _avgMoving = _avgMoving == 0 ? _speed : _avgMoving * 0.9 + _speed * 0.1;
    if (deviceHeadingDeg >= 0 && deviceHeadingDeg <= 360 && _speed > 1.0) {
      _heading = deviceHeadingDeg;
    } else if (d > 10) {
      _heading = bearing(last, p);
    }
    _last = p;
    _lastAt = at;
    return FilterResult(FixVerdict.accepted, FilteredFix(p, accuracyM, _speed, _speed > 0.8 ? _heading : null, at));
  }
}
