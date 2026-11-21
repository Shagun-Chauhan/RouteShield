import 'package:flutter_test/flutter_test.dart';
import '../lib/services/emergency_alert.dart';

void main() {
  final now = DateTime(2026, 11, 21, 14, 47);

  test('includes OSM link, coordinates, battery and timestamp', () {
    final m = AlertMessage.compose(
      name: 'Asha', battery: 17, threshold: 20, now: now,
      fix: LocationFix(lat: 18.5204, lng: 73.8567, at: now.subtract(const Duration(minutes: 2))),
    );
    expect(m, contains('https://www.openstreetmap.org/?mlat=18.520400&mlon=73.856700'));
    expect(m, contains('Battery level: 17%'));
    expect(m, contains('Asha'));
    expect(m, isNot(contains('OUT OF DATE')));
  });

  test('marks stale location', () {
    final m = AlertMessage.compose(
      name: null, battery: 15, threshold: 20, now: now,
      fix: LocationFix(lat: 1, lng: 2, at: now.subtract(const Duration(hours: 3))),
    );
    expect(m, contains('OUT OF DATE'));
    expect(m, contains('3 h ago'));
  });

  test('never invents a location', () {
    final m = AlertMessage.compose(name: 'A', battery: 15, threshold: 20, now: now);
    expect(m, contains('not available'));
    expect(m, isNot(contains('openstreetmap')));
  });
}
