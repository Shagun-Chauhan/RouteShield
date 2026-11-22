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
  final int? startIndex, endIndex; // inclusive indices into RouteOption.path (from server; null = no geometry)
  const SegmentAssessment({
    required this.id, required this.name, required this.riskLevel, required this.confidenceLevel,
    this.riskScore, this.confidence = 0, this.freshestEvidenceAt,
    this.reasons = const [], this.missingInformation = const [], this.startIndex, this.endIndex,
  });
  factory SegmentAssessment.fromJson(Map<String, dynamic> j) => SegmentAssessment(
        id: '${j['id']}', name: j['name'] ?? 'Segment',
        riskLevel: j['riskLevel'] ?? 'unknown', confidenceLevel: j['confidenceLevel'] ?? 'low',
        riskScore: (j['riskScore'] as num?)?.toInt(), confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        freshestEvidenceAt: _dt(j['freshestEvidenceAt']),
        reasons: List<String>.from(j['reasons'] ?? const []),
        missingInformation: List<String>.from(j['missingInformation'] ?? const []),
        startIndex: (j['startIndex'] as num?)?.toInt(), endIndex: (j['endIndex'] as num?)?.toInt(),
      );
}

/// One routing-provider manoeuvre (e.g. an OSRM step). Comes from the server's optional `steps`
/// array. The app never invents steps. Position is [pathIndex] (index into RouteOption.path) or,
/// failing that, the manoeuvre [location].
class RouteStep {
  final String instruction; // human text, e.g. "Turn left onto MG Road"
  final String? maneuver, modifier, roadName; // OSRM: type (turn, arrive, ...) / modifier (left, slight right, ...)
  final double distanceM; // length of the leg that starts at this manoeuvre
  final int? pathIndex;
  final GeoPoint? location;
  const RouteStep({required this.instruction, this.maneuver, this.modifier, this.roadName, this.distanceM = 0, this.pathIndex, this.location});
  factory RouteStep.fromJson(Map<String, dynamic> j) {
    final m = j['maneuver'];
    final mm = m is Map ? Map<String, dynamic>.from(m) : const <String, dynamic>{};
    final loc = j['location'] ?? mm['location'];
    GeoPoint? point;
    if (loc is Map && loc['lat'] is num && loc['lng'] is num) {
      point = GeoPoint((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
    }
    final type = (m is String ? m : mm['type'] ?? j['type'])?.toString();
    return RouteStep(
      instruction: '${j['instruction'] ?? ''}',
      maneuver: type,
      modifier: (mm['modifier'] ?? j['modifier'])?.toString(),
      roadName: (j['name'] ?? j['roadName'])?.toString(),
      distanceM: (j['distanceM'] as num?)?.toDouble() ?? (j['distance'] as num?)?.toDouble() ?? 0,
      pathIndex: (j['pathIndex'] as num?)?.toInt() ?? (j['startIndex'] as num?)?.toInt(),
      location: point,
    );
  }
}

class RouteOption {
  final String id, label, riskLevel, confidenceLevel, explanation; // label: Safety-prioritised|Balanced|Time-prioritised
  final int durationMin, extraMin;
  final double distanceKm;
  final bool recommended, isDemo;
  final List<SegmentAssessment> segments;
  final List<GeoPoint> path;
  final List<RouteStep> steps; // empty when the server supplied no manoeuvres
  const RouteOption({
    required this.id, required this.label, required this.riskLevel, required this.confidenceLevel,
    required this.explanation, required this.durationMin, required this.extraMin, required this.distanceKm,
    this.recommended = false, this.isDemo = false, this.segments = const [], this.path = const [], this.steps = const [],
  });
  factory RouteOption.fromJson(Map<String, dynamic> j) => RouteOption(
        id: '${j['id']}', label: j['label'] ?? 'Balanced', riskLevel: j['riskLevel'] ?? 'unknown',
        confidenceLevel: j['confidenceLevel'] ?? 'low', explanation: j['explanation'] ?? '',
        durationMin: (j['durationMin'] as num?)?.toInt() ?? 0, extraMin: (j['extraMin'] as num?)?.toInt() ?? 0,
        distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0, recommended: j['recommended'] == true,
        segments: (j['segments'] as List? ?? []).map((e) => SegmentAssessment.fromJson(e)).toList(),
        path: (j['path'] as List? ?? []).map((e) => GeoPoint.fromJson(e)).toList(),
        steps: (j['steps'] as List? ?? []).map((e) => RouteStep.fromJson(Map<String, dynamic>.from(e as Map))).where((s) => s.instruction.isNotEmpty).toList(),
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
