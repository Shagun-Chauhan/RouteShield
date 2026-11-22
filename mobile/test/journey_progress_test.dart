import 'package:flutter_test/flutter_test.dart';
import 'package:routeshield/models/models.dart';
import 'package:routeshield/services/journey_progress.dart';

void main() {
  const path = [GeoPoint(18.50, 73.85), GeoPoint(18.51, 73.85), GeoPoint(18.52, 73.85)];

  test('start of route: almost nothing completed', () {
    final p = journeyProgress(const GeoPoint(18.50, 73.85), path)!;
    expect(p.fraction, closeTo(0, 0.01));
    expect(p.remainingM, closeTo(2224, 30));
  });

  test('midpoint: about half remaining', () {
    final p = journeyProgress(const GeoPoint(18.51, 73.8502), path)!;
    expect(p.fraction, closeTo(0.5, 0.02));
  });

  test('past the end clamps to zero remaining', () {
    final p = journeyProgress(const GeoPoint(18.53, 73.85), path)!;
    expect(p.remainingM, closeTo(0, 1));
  });

  test('path with fewer than 2 points gives null', () {
    expect(journeyProgress(const GeoPoint(0, 0), const [GeoPoint(0, 0)]), isNull);
  });
}
