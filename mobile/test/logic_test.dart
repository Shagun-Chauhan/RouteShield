import 'package:flutter_test/flutter_test.dart';
import 'package:routeshield/models/models.dart';
import 'package:routeshield/services/deviation_detector.dart';
import 'package:routeshield/services/safety_plan.dart';

void main() {
  const path = [GeoPoint(18.5286, 73.8744), GeoPoint(18.5204, 73.8600), GeoPoint(18.5120, 73.8480)];

  test('point on route is ~0 m from path', () {
    expect(distanceToPathMeters(path[1], path), lessThan(1));
  });

  test('single drifting fix does not trigger deviation', () {
    final d = DeviationDetector();
    const far = GeoPoint(18.5400, 73.9000);
    expect(d.update(far, 10, path), isFalse);
  });

  test('three consecutive accurate far fixes trigger deviation', () {
    final d = DeviationDetector();
    const far = GeoPoint(18.5400, 73.9000);
    d.update(far, 10, path);
    d.update(far, 10, path);
    expect(d.update(far, 10, path), isTrue);
  });

  test('poor-accuracy fixes are ignored and returning to route resets', () {
    final d = DeviationDetector();
    const far = GeoPoint(18.5400, 73.9000);
    d.update(far, 10, path);
    d.update(far, 200, path); // ignored
    d.update(path[1], 10, path); // reset
    d.update(far, 10, path);
    expect(d.update(far, 10, path), isFalse);
  });

  test('missed check-in plan says it is not an emergency and mentions 112', () {
    final steps = compilePlan(Situation.missedCheckIn, hasContacts: true);
    final text = steps.map((s) => '${s.title} ${s.detail}').join(' ');
    expect(text, contains('not treated as proof of an emergency'));
    expect(text, contains('112'));
  });

  test('plan asks to add a contact when none exist', () {
    final steps = compilePlan(Situation.lowBattery, hasContacts: false, batteryPct: 9);
    expect(steps.any((s) => s.title == 'Add a trusted contact'), isTrue);
  });
}
