import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../providers/providers.dart';

/// Talks to the Express backend. If the server is unreachable (or the user is in
/// demo mode) it falls back to clearly labelled DEMO data and raises the demo banner.
/// Demo data is sample data and is never live information.
class Repository {
  final Ref ref;
  Repository(this.ref);
  ApiClient get api => ref.read(apiClientProvider);

  final _contacts = <TrustedContact>[];
  final _reports = <SafetyReport>[];
  final _journeys = <Journey>[];
  final _notifs = <AppNotification>[
    AppNotification(id: 'd1', title: 'Demo mode', body: 'The RouteShield server is not connected. Sample data is shown and is not live.', at: DateTime.now()),
  ];

  void _setDemo() => Future.microtask(() => ref.read(demoActiveProvider.notifier).state = true);

  Future<T> _try<T>(Future<T> Function() live, T Function() demo) async {
    if (api.token == 'demo') {
      _setDemo();
      return demo();
    }
    try {
      return await live();
    } on NetworkException {
      _setDemo();
      return demo();
    }
  }

  List<T> _list<T>(dynamic body, String key, T Function(Map<String, dynamic>) f) =>
      ((body is Map ? body[key] : body) as List? ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();

  // ---------- Auth ----------
  Future<AuthResult> login(String email, String password) async {
    try {
      final b = await api.post('/auth/login', {'email': email, 'password': password});
      return AuthResult(b['token'], b['user']['name'] ?? email);
    } on NetworkException {
      _setDemo();
      return AuthResult('demo', email.split('@').first);
    }
  }

  Future<AuthResult> register(String name, String email, String password) async {
    try {
      final b = await api.post('/auth/register', {'name': name, 'email': email, 'password': password});
      return AuthResult(b['token'], b['user']['name'] ?? name);
    } on NetworkException {
      _setDemo();
      return AuthResult('demo', name);
    }
  }

  // ---------- Routes ----------
  Future<List<RouteOption>> fetchRoutes(GeoPoint origin, String destination) => _try(
        () async => _list(await api.get('/routes', {'origin': '${origin.lat},${origin.lng}', 'destination': destination}), 'routes', RouteOption.fromJson),
        () => _demoRoutes(destination),
      );

  // ---------- Contacts ----------
  Future<List<TrustedContact>> contacts() => _try(
        () async => _list(await api.get('/contacts'), 'contacts', TrustedContact.fromJson),
        () => List.of(_contacts),
      );

  Future<void> addContact(String name, String phone, bool consent) => _try<void>(
        () async { await api.post('/contacts', {'name': name, 'phone': phone, 'consentToShare': consent}); },
        () { _contacts.add(TrustedContact(id: 'c${_contacts.length + 1}', name: name, phone: phone, consentToShare: consent)); },
      );

  Future<void> removeContact(String id) => _try<void>(() async { await api.delete('/contacts/$id'); }, () { _contacts.removeWhere((c) => c.id == id); });

  // ---------- Journeys ----------
  Future<Journey> startJourney(String destination, RouteOption route, int checkInMinutes, List<String> contactIds) {
    final now = DateTime.now();
    final eta = now.add(Duration(minutes: route.durationMin));
    return _try(
      () async {
        final b = await api.post('/journeys', {
          'destination': destination, 'routeId': route.id, 'expectedArrival': eta.toUtc().toIso8601String(),
          'checkInMinutes': checkInMinutes, 'contactIds': contactIds,
        });
        return Journey.fromJson(Map<String, dynamic>.from(b['journey']));
      },
      () {
        final j = Journey(id: 'j${_journeys.length + 1}', destination: destination, status: 'active', startedAt: now, expectedArrival: eta, checkInMinutes: checkInMinutes, contactIds: contactIds, isDemo: true);
        _journeys.insert(0, j);
        return j;
      },
    );
  }

  Future<void> checkIn(String journeyId) => _try<void>(() async { await api.post('/journeys/$journeyId/check-in', {}); }, () {});

  Future<void> completeJourney(String journeyId, {bool cancelled = false}) => _try<void>(
        () async { await api.post('/journeys/$journeyId/${cancelled ? 'cancel' : 'complete'}', {}); },
        () {
          final i = _journeys.indexWhere((j) => j.id == journeyId);
          if (i >= 0) {
            final o = _journeys[i];
            _journeys[i] = Journey(id: o.id, destination: o.destination, status: cancelled ? 'cancelled' : 'completed', startedAt: o.startedAt, expectedArrival: o.expectedArrival, checkInMinutes: o.checkInMinutes, contactIds: o.contactIds, isDemo: true);
          }
        },
      );

  Future<List<Journey>> history() => _try(() async => _list(await api.get('/journeys'), 'journeys', Journey.fromJson), () => List.of(_journeys));

  // ---------- Reports ----------
  Future<List<SafetyReport>> reports() => _try(() async => _list(await api.get('/reports'), 'reports', SafetyReport.fromJson), () => List.of(_reports));

  Future<void> submitReport(String category, String description, bool approximate, GeoPoint? at) => _try<void>(
        () async { await api.post('/reports', {'category': category, 'description': description, 'approximateLocation': approximate, if (at != null) 'location': at.toJson()}); },
        () { _reports.insert(0, SafetyReport(id: 'r${_reports.length + 1}', category: category, description: description, status: 'pending', createdAt: DateTime.now(), expiresAt: DateTime.now().add(const Duration(days: 14)), approximateLocation: approximate)); },
      );

  // ---------- Notifications ----------
  Future<List<AppNotification>> notifications() => _try(() async => _list(await api.get('/notifications'), 'notifications', AppNotification.fromJson), () => List.of(_notifs));

  // ---------- Safe havens ----------
  Future<List<SafeHaven>> safeHavens(GeoPoint at) => _try(
        () async => _list(await api.get('/places/safe-havens', {'lat': '${at.lat}', 'lng': '${at.lng}'}), 'places', SafeHaven.fromJson),
        () => const [
          SafeHaven(name: 'Sample Hospital (demo)', type: 'hospital', location: GeoPoint(18.5230, 73.8590), distanceM: 650, isDemo: true),
          SafeHaven(name: 'Sample Police Station (demo)', type: 'police', location: GeoPoint(18.5180, 73.8530), distanceM: 1100, isDemo: true),
        ],
      );

  // ---------- Demo routes (sample data, labelled) ----------
  SegmentAssessment _seg(String id, String name, String risk, String conf, {int? score, double c = 0.3, List<String> reasons = const [], List<String> missing = const []}) =>
      SegmentAssessment(id: id, name: '$name (demo)', riskLevel: risk, confidenceLevel: conf, riskScore: score, confidence: c, reasons: reasons, missingInformation: missing,
          freshestEvidenceAt: risk == 'unknown' ? null : DateTime.now().subtract(const Duration(days: 3)));

  List<RouteOption> _demoRoutes(String dest) => [
        RouteOption(
          id: 'demo-a', label: 'Safety-prioritised', durationMin: 31, extraMin: 7, distanceKm: 9.8, riskLevel: 'low', confidenceLevel: 'medium', recommended: true, isDemo: true,
          explanation: 'DEMO: Sample route that avoids the segment with poor lighting. It adds 7 minutes. Sample data only, not live.',
          path: const [GeoPoint(18.5286, 73.8744), GeoPoint(18.5240, 73.8680), GeoPoint(18.5204, 73.8600), GeoPoint(18.5170, 73.8540), GeoPoint(18.5120, 73.8480)],
          segments: [
            _seg('a1', 'Station Road', 'low', 'medium', score: 12, c: 0.55, reasons: ['Lighting reported as good'], missing: ['Incident records']),
            _seg('a2', 'Main Avenue', 'low', 'medium', score: 18, c: 0.5, missing: ['Community reports']),
            _seg('a3', 'Market Lane', 'unknown', 'low', missing: ['Lighting information', 'Road condition information', 'Incident records', 'Community reports'], reasons: ['No evidence available: risk cannot be estimated (this does not mean the road is safe)']),
          ],
        ),
        RouteOption(
          id: 'demo-b', label: 'Balanced', durationMin: 27, extraMin: 3, distanceKm: 8.6, riskLevel: 'moderate', confidenceLevel: 'medium', isDemo: true,
          explanation: 'DEMO: Sample compromise between time and estimated risk. One segment has a sample poor-lighting report.',
          path: const [GeoPoint(18.5286, 73.8744), GeoPoint(18.5230, 73.8650), GeoPoint(18.5160, 73.8560), GeoPoint(18.5120, 73.8480)],
          segments: [
            _seg('b1', 'Station Road', 'low', 'medium', score: 12, c: 0.55),
            _seg('b2', 'River Bypass', 'moderate', 'low', score: 34, c: 0.3, reasons: ['Lighting reported as poor', 'Low evidence confidence: treat this estimate cautiously'], missing: ['Incident records']),
          ],
        ),
        RouteOption(
          id: 'demo-c', label: 'Time-prioritised', durationMin: 24, extraMin: 0, distanceKm: 7.9, riskLevel: 'unknown', confidenceLevel: 'low', isDemo: true,
          explanation: 'DEMO: Fastest sample route. Little sample evidence exists, so its risk is unknown, which is not the same as safe.',
          path: const [GeoPoint(18.5286, 73.8744), GeoPoint(18.5200, 73.8620), GeoPoint(18.5120, 73.8480)],
          segments: [_seg('c1', 'Highway Link', 'unknown', 'low', missing: ['Lighting information', 'Road condition information', 'Incident records', 'Community reports'], reasons: ['No evidence available: risk cannot be estimated (this does not mean the road is safe)'])],
        ),
      ];
}
