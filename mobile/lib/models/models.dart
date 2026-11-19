class GeoPoint {
  final double lat, lng;
  const GeoPoint(this.lat, this.lng);
  factory GeoPoint.fromJson(Map<String, dynamic> j) =>
      GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class SegmentAssessment {
  final String id, name, riskLevel, confidenceLevel; // riskLevel: low|moderate|high|unknown
  final int? riskScore;
  final double confidence;
  final DateTime? freshestEvidenceAt;
  final List<String> reasons, missingInformation;
  const SegmentAssessment({
    required this.id, required this.name, required this.riskLevel, required this.confidenceLevel,
    this.riskScore, this.confidence = 0, this.freshestEvidenceAt,
    this.reasons = const [], this.missingInformation = const [],
  });
  factory SegmentAssessment.fromJson(Map<String, dynamic> j) => SegmentAssessment(
        id: '${j['id']}', name: j['name'] ?? 'Segment',
        riskLevel: j['riskLevel'] ?? 'unknown', confidenceLevel: j['confidenceLevel'] ?? 'low',
        riskScore: (j['riskScore'] as num?)?.toInt(), confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        freshestEvidenceAt: _dt(j['freshestEvidenceAt']),
        reasons: List<String>.from(j['reasons'] ?? const []),
        missingInformation: List<String>.from(j['missingInformation'] ?? const []),
      );
}

class RouteOption {
  final String id, label, riskLevel, confidenceLevel, explanation; // label: Safety-prioritised|Balanced|Time-prioritised
  final int durationMin, extraMin;
  final double distanceKm;
  final bool recommended, isDemo;
  final List<SegmentAssessment> segments;
  final List<GeoPoint> path;
  const RouteOption({
    required this.id, required this.label, required this.riskLevel, required this.confidenceLevel,
    required this.explanation, required this.durationMin, required this.extraMin, required this.distanceKm,
    this.recommended = false, this.isDemo = false, this.segments = const [], this.path = const [],
  });
  factory RouteOption.fromJson(Map<String, dynamic> j) => RouteOption(
        id: '${j['id']}', label: j['label'] ?? 'Balanced', riskLevel: j['riskLevel'] ?? 'unknown',
        confidenceLevel: j['confidenceLevel'] ?? 'low', explanation: j['explanation'] ?? '',
        durationMin: (j['durationMin'] as num?)?.toInt() ?? 0, extraMin: (j['extraMin'] as num?)?.toInt() ?? 0,
        distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0, recommended: j['recommended'] == true,
        segments: (j['segments'] as List? ?? []).map((e) => SegmentAssessment.fromJson(e)).toList(),
        path: (j['path'] as List? ?? []).map((e) => GeoPoint.fromJson(e)).toList(),
      );
}

class TrustedContact {
  final String id, name, phone;
  final bool consentToShare;
  const TrustedContact({required this.id, required this.name, required this.phone, required this.consentToShare});
  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
      id: '${j['id'] ?? j['_id']}', name: j['name'] ?? '', phone: j['phone'] ?? '', consentToShare: j['consentToShare'] == true);
}

class Journey {
  final String id, destination, status; // active|completed|cancelled
  final DateTime startedAt, expectedArrival;
  final int checkInMinutes;
  final List<String> contactIds;
  final bool isDemo;
  const Journey({
    required this.id, required this.destination, required this.status, required this.startedAt,
    required this.expectedArrival, required this.checkInMinutes, this.contactIds = const [], this.isDemo = false,
  });
  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
        id: '${j['id'] ?? j['_id']}', destination: j['destination'] ?? '', status: j['status'] ?? 'active',
        startedAt: _dt(j['startedAt']) ?? DateTime.now(), expectedArrival: _dt(j['expectedArrival']) ?? DateTime.now(),
        checkInMinutes: (j['checkInMinutes'] as num?)?.toInt() ?? 15,
        contactIds: List<String>.from(j['contactIds'] ?? const []),
      );
}

class SafetyReport {
  final String id, category, description, status; // pending|verified|rejected|expired
  final DateTime createdAt, expiresAt;
  final bool approximateLocation;
  const SafetyReport({
    required this.id, required this.category, required this.description, required this.status,
    required this.createdAt, required this.expiresAt, this.approximateLocation = true,
  });
  factory SafetyReport.fromJson(Map<String, dynamic> j) => SafetyReport(
        id: '${j['id'] ?? j['_id']}', category: j['category'] ?? 'hazard', description: j['description'] ?? '',
        status: j['status'] ?? 'pending', createdAt: _dt(j['createdAt']) ?? DateTime.now(),
        expiresAt: _dt(j['expiresAt']) ?? DateTime.now().add(const Duration(days: 14)),
        approximateLocation: j['approximateLocation'] != false,
      );
}

class AppNotification {
  final String id, title, body;
  final DateTime at;
  const AppNotification({required this.id, required this.title, required this.body, required this.at});
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
      id: '${j['id'] ?? j['_id']}', title: j['title'] ?? '', body: j['body'] ?? '', at: _dt(j['createdAt']) ?? DateTime.now());
}

class SafeHaven {
  final String name, type; // hospital|police|public
  final GeoPoint location;
  final double distanceM;
  final bool? openNow; // null = unknown, never invented
  final String? hours;
  final bool isDemo;
  const SafeHaven({required this.name, required this.type, required this.location, required this.distanceM, this.openNow, this.hours, this.isDemo = false});
  factory SafeHaven.fromJson(Map<String, dynamic> j) => SafeHaven(
        name: j['name'] ?? '', type: j['type'] ?? 'public', location: GeoPoint.fromJson(j['location']),
        distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0, openNow: j['openNow'] as bool?, hours: j['hours'] as String?,
      );
}

class AuthResult {
  final String token, name;
  const AuthResult(this.token, this.name);
}
