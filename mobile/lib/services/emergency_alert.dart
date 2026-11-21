import 'package:intl/intl.dart';

enum AlertStatus { queued, accepted, partial, failed, noContacts, skipped, manualOpened }

const staleAfter = Duration(minutes: 10);

class LocationFix {
  const LocationFix({required this.lat, required this.lng, required this.at, this.accuracy});
  final double lat, lng;
  final DateTime at;
  final double? accuracy;

  String get osmLink {
    final a = lat.toStringAsFixed(6), o = lng.toStringAsFixed(6);
    return 'https://www.openstreetmap.org/?mlat=$a&mlon=$o#map=17/$a/$o';
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'at': at.toIso8601String(), 'acc': accuracy};
  factory LocationFix.fromJson(Map<String, dynamic> j) => LocationFix(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        at: DateTime.parse(j['at'] as String),
        accuracy: (j['acc'] as num?)?.toDouble(),
      );
}

class EmergencyAlertRecord {
  const EmergencyAlertRecord({
    required this.id,
    required this.createdAt,
    required this.battery,
    required this.status,
    this.fix,
    this.attempts = 0,
    this.nextRetryAt,
    this.detail = '',
    this.accepted = 0,
    this.total = 0,
  });

  final String id; // episode id (also the server idempotency key)
  final DateTime createdAt;
  final int battery;
  final AlertStatus status;
  final LocationFix? fix;
  final int attempts;
  final DateTime? nextRetryAt;
  final String detail;
  final int accepted, total;

  bool get locationStale => fix != null && createdAt.difference(fix!.at) > staleAfter;

  EmergencyAlertRecord copyWith({
    int? battery,
    LocationFix? fix,
    AlertStatus? status,
    int? attempts,
    DateTime? nextRetryAt,
    bool clearRetry = false,
    String? detail,
    int? accepted,
    int? total,
  }) =>
      EmergencyAlertRecord(
        id: id,
        createdAt: createdAt,
        battery: battery ?? this.battery,
        status: status ?? this.status,
        fix: fix ?? this.fix,
        attempts: attempts ?? this.attempts,
        nextRetryAt: clearRetry ? null : (nextRetryAt ?? this.nextRetryAt),
        detail: detail ?? this.detail,
        accepted: accepted ?? this.accepted,
        total: total ?? this.total,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'battery': battery,
        'status': status.name,
        'fix': fix?.toJson(),
        'attempts': attempts,
        'nextRetryAt': nextRetryAt?.toIso8601String(),
        'detail': detail,
        'accepted': accepted,
        'total': total,
      };

  factory EmergencyAlertRecord.fromJson(Map<String, dynamic> j) => EmergencyAlertRecord(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        battery: j['battery'] as int,
        status: AlertStatus.values.asNameMap()[j['status']] ?? AlertStatus.failed,
        fix: j['fix'] == null ? null : LocationFix.fromJson(Map<String, dynamic>.from(j['fix'] as Map)),
        attempts: (j['attempts'] as int?) ?? 0,
        nextRetryAt: j['nextRetryAt'] == null ? null : DateTime.parse(j['nextRetryAt'] as String),
        detail: (j['detail'] as String?) ?? '',
        accepted: (j['accepted'] as int?) ?? 0,
        total: (j['total'] as int?) ?? 0,
      );
}

String ageText(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

class AlertMessage {
  /// Used for the user-confirmed SMS fallback. The server builds the same text
  /// for automatic sending (backend/routes/lowBatteryAlert.js).
  static String compose({
    required String? name,
    required int battery,
    required int threshold,
    required DateTime now,
    LocationFix? fix,
  }) {
    final who = (name == null || name.trim().isEmpty) ? 'Your trusted contact' : name.trim();
    final f = DateFormat('d MMM yyyy, HH:mm');
    final String loc;
    if (fix == null) {
      loc = 'Last location: not available (no location has been recorded).';
    } else {
      final stale = now.difference(fix.at) > staleAfter;
      loc = 'Last available location:\n${fix.osmLink}\n'
          'Location recorded: ${f.format(fix.at)} (${ageText(now.difference(fix.at))})'
          '${stale ? ' - OUT OF DATE, may not be their current position' : ''}';
    }
    return 'ROUTESHIELD SAFETY ALERT\n\n'
        '$who\'s phone battery has reached a critical level ($threshold% or below).\n\n'
        '$loc\n\n'
        'Battery level: $battery%\n'
        'Time: ${f.format(now)}\n\n'
        'This is an automatic low-battery safety notification. Please try contacting them if necessary.';
  }
}
