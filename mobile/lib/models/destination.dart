import 'models.dart';

/// A chosen destination. [point] is set when it came from geocoding; null for
/// legacy free-text destinations (recent searches, "Recover route").
/// Value equality so it can be a Riverpod family key.
class Destination {
  final String label;
  final GeoPoint? point;
  const Destination(this.label, [this.point]);
  @override
  bool operator ==(Object o) => o is Destination && o.label == label && o.point?.lat == point?.lat && o.point?.lng == point?.lng;
  @override
  int get hashCode => Object.hash(label, point?.lat, point?.lng);
}
