import 'package:flutter_test/flutter_test.dart';
import 'package:routeshield/models/models.dart';
import 'package:routeshield/services/gps_filter.dart';
import 'package:routeshield/services/journey_progress.dart';
import 'package:routeshield/services/navigation_engine.dart';
import 'package:routeshield/services/opening_hours.dart';

// NOTE: package name `routeshield` is assumed; change it to the `name:` in your pubspec.yaml.

// ~111 m per 0.001 deg latitude.
List<GeoPoint> line() => [for (var i = 0; i <= 10; i++) GeoPoint(18.5 + i * 0.001, 73.85)];

void main() {
  group('opening hours', () {
    final mon10 = DateTime(2026, 11, 23, 10); // Monday
    test('open inside range', () {
      final s = OpeningHours.statusOf('Mo-Fr 09:00-18:00', mon10);
      expect(s.state, OpenState.open);
      expect(s.label, contains('closes 18:00'));
    });
    test('closed shows next opening', () {
      final s = OpeningHours.statusOf('Mo-Fr 09:00-18:00', DateTime(2026, 11, 23, 20));
      expect(s.state, OpenState.closed);
      expect(s.label, contains('opens tomorrow 09:00'));
    });
    test('later rule overrides earlier for the same day', () {
      expect(OpeningHours.statusOf('Mo-Su 09:00-18:00; Mo off', mon10).state, OpenState.closed);
    });
    test('overnight range spills into next day', () {
      final s = OpeningHours.statusOf('Mo 18:00-02:00', DateTime(2026, 11, 24, 1)); // Tuesday 01:00
      expect(s.state, OpenState.open);
    });
    test('missing or unsupported never means open', () {
      expect(OpeningHours.statusOf(null, mon10).state, OpenState.unknown);
      expect(OpeningHours.statusOf('sunrise-sunset', mon10).state, OpenState.unknown);
      expect(OpeningHours.statusOf('Jan-Mar Mo 09:00-10:00', mon10).state, OpenState.unknown);
    });
    test('24/7', () => expect(OpeningHours.statusOf('24/7', mon10).state, OpenState.open));
    test('PH rule flags uncertainty', () {
      expect(OpeningHours.statusOf('Mo-Fr 09:00-18:00; PH off', mon10).uncertain, isTrue);
    });
  });

  group('gps filter', () {
    final t0 = DateTime(2026, 1, 1, 12);
    test('rejects poor accuracy', () {
      final r = GpsFilter().update(const GeoPoint(18.5, 73.85), 120, t0);
      expect(r.verdict, FixVerdict.rejectedAccuracy);
    });
    test('rejects impossible jump', () {
      final f = GpsFilter();
      f.update(const GeoPoint(18.5, 73.85), 10, t0);
      final r = f.update(const GeoPoint(18.6, 73.85), 10, t0.add(const Duration(seconds: 1)));
      expect(r.verdict, FixVerdict.rejectedJump);
    });
    test('jitter while standing adds no distance', () {
      final f = GpsFilter();
      f.update(const GeoPoint(18.5, 73.85), 10, t0);
      for (var i = 1; i < 6; i++) {
        f.update(GeoPoint(18.5 + i * 0.00001, 73.85), 10, t0.add(Duration(seconds: i)));
      }
      expect(f.distanceTravelledM, 0);
    });
    test('real movement accumulates distance', () {
      final f = GpsFilter();
      f.update(const GeoPoint(18.5, 73.85), 5, t0);
      f.update(const GeoPoint(18.501, 73.85), 5, t0.add(const Duration(seconds: 10)));
      expect(f.distanceTravelledM, closeTo(111, 5));
    });
  });

  group('route progress', () {
    test('along / remaining / off-route', () {
      final g = RouteGeometry(line());
      final m = g.match(const GeoPoint(18.505, 73.8505))!;
      expect(m.alongM, closeTo(g.totalM / 2, 15));
      expect(m.offRouteM, closeTo(53, 10));
    });
    test('windowed match does not jump to a later pass', () {
      final g = RouteGeometry(line());
      expect(g.match(const GeoPoint(18.5005, 73.85), hintSegment: 0)!.segment, 0);
    });
  });

  group('navigation engine', () {
    final path = line();
    final route = RouteOption(
      id: 'r', label: 'Balanced', riskLevel: 'low', confidenceLevel: 'medium', explanation: '', durationMin: 20, extraMin: 0, distanceKm: 1.1,
      path: path,
      steps: const [
        RouteStep(instruction: 'Turn left', maneuver: 'turn', modifier: 'left', pathIndex: 4),
        RouteStep(instruction: 'Arrive', maneuver: 'arrive', pathIndex: 10),
      ],
      segments: const [
        SegmentAssessment(id: 'a', name: 'A', riskLevel: 'low', confidenceLevel: 'high', startIndex: 0, endIndex: 5),
        SegmentAssessment(id: 'b', name: 'B', riskLevel: 'high', confidenceLevel: 'low', startIndex: 5, endIndex: 10),
      ],
    );
    final e = NavigationEngine(route);
    test('next step comes from provider steps and distance shrinks', () {
      final a = e.nextStep(0)!;
      expect(a.step.instruction, 'Turn left');
      expect(a.distanceM, closeTo(e.geometry.cum[4], 1));
      expect(e.nextStep(e.geometry.cum[4] + 100)!.step.instruction, 'Arrive');
    });
    test('no steps from server => no invented instructions', () {
      final bare = NavigationEngine(RouteOption(id: 'x', label: 'x', riskLevel: 'low', confidenceLevel: 'low', explanation: '', durationMin: 5, extraMin: 0, distanceKm: 1, path: path));
      expect(bare.hasSteps, isFalse);
      expect(bare.nextStep(0), isNull);
    });
    test('upcoming high-risk segment', () {
      final r = e.upcomingRisk(0)!;
      expect(r.segment.id, 'b');
    });
    test('eta uses planned pace when stationary', () {
      final eta = e.eta(1000, 0)!;
      expect(eta.basis, 'planned pace');
    });
  });
}
