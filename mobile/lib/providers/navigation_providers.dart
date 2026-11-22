import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../core/nav_config.dart';
import '../models/destination.dart';
import '../models/models.dart';
import '../services/deviation_detector.dart';
import '../services/gps_filter.dart';
import '../services/live_location.dart';
import '../services/location_service.dart';
import '../services/navigation_engine.dart';
import '../services/notification_service.dart';
import 'providers.dart';
import 'survival_providers.dart' show survivalProfileProvider;

/// waiting: no fix yet | good: recent accepted fix | quiet: no update lately (often just standing still,
/// the device only reports movement) | poor: fixes arriving but too inaccurate to use | unavailable:
/// permission denied, location off or the stream failed.
enum GpsStatus { waiting, good, quiet, poor, unavailable }

/// Journey phase as seen by navigation. (planned = route preview, before this controller starts;
/// completed/cancelled = controller back to idle after JourneyService.finish succeeded.)
enum JourneyPhase { idle, active, paused, arrivedPendingConfirmation }

/// Shown once after a journey is completed.
class JourneySummary {
  final String destination;
  final Duration duration;
  final double travelledM;
  final bool arrivedDetected;
  final bool cancelled;
  const JourneySummary(this.destination, this.duration, this.travelledM, this.arrivedDetected, this.cancelled);
}

class RerouteProposal {
  final RouteOption candidate;
  final DateTime at;
  const RerouteProposal(this.candidate, this.at);
}

const _unset = Object();
T? _pick<T>(Object? v, T? old) => identical(v, _unset) ? old : v as T?;

class NavState {
  final bool active, paused, arrived, arrivalDismissed, deviated, rerouting;
  final GpsStatus gps;
  final FilteredFix? fix;
  final DateTime? fixAt;
  final double? rawAccuracyM;
  final double travelledM;
  final double? remainingM, fraction;
  final bool routeHasSteps;
  final StepInfo? next;
  final UpcomingRisk? risk;
  final DateTime? eta;
  final String etaBasis;
  final RerouteProposal? proposal;
  final String? rerouteMessage;
  final DateTime? nextCheckIn;
  final bool checkInDue, checkInMissed;

  const NavState({
    this.active = false, this.paused = false, this.arrived = false, this.arrivalDismissed = false, this.deviated = false, this.rerouting = false,
    this.gps = GpsStatus.waiting, this.fix, this.fixAt, this.rawAccuracyM, this.travelledM = 0,
    this.remainingM, this.fraction, this.routeHasSteps = false, this.next, this.risk, this.eta, this.etaBasis = '',
    this.proposal, this.rerouteMessage, this.nextCheckIn, this.checkInDue = false, this.checkInMissed = false,
  });

  JourneyPhase get phase => !active
      ? JourneyPhase.idle
      : arrived
          ? JourneyPhase.arrivedPendingConfirmation
          : paused
              ? JourneyPhase.paused
              : JourneyPhase.active;

  NavState copyWith({
    bool? active, bool? paused, bool? arrived, bool? arrivalDismissed, bool? deviated, bool? rerouting, GpsStatus? gps,
    Object? fix = _unset, Object? fixAt = _unset, Object? rawAccuracyM = _unset, double? travelledM,
    Object? remainingM = _unset, Object? fraction = _unset, bool? routeHasSteps,
    Object? next = _unset, Object? risk = _unset, Object? eta = _unset, String? etaBasis,
    Object? proposal = _unset, Object? rerouteMessage = _unset, Object? nextCheckIn = _unset,
    bool? checkInDue, bool? checkInMissed,
  }) =>
      NavState(
        active: active ?? this.active, paused: paused ?? this.paused, arrived: arrived ?? this.arrived, arrivalDismissed: arrivalDismissed ?? this.arrivalDismissed,
        deviated: deviated ?? this.deviated, rerouting: rerouting ?? this.rerouting, gps: gps ?? this.gps,
        fix: _pick<FilteredFix>(fix, this.fix), fixAt: _pick<DateTime>(fixAt, this.fixAt),
        rawAccuracyM: _pick<double>(rawAccuracyM, this.rawAccuracyM), travelledM: travelledM ?? this.travelledM,
        remainingM: _pick<double>(remainingM, this.remainingM), fraction: _pick<double>(fraction, this.fraction),
        routeHasSteps: routeHasSteps ?? this.routeHasSteps, next: _pick<StepInfo>(next, this.next),
        risk: _pick<UpcomingRisk>(risk, this.risk), eta: _pick<DateTime>(eta, this.eta), etaBasis: etaBasis ?? this.etaBasis,
        proposal: _pick<RerouteProposal>(proposal, this.proposal),
        rerouteMessage: _pick<String>(rerouteMessage, this.rerouteMessage),
        nextCheckIn: _pick<DateTime>(nextCheckIn, this.nextCheckIn),
        checkInDue: checkInDue ?? this.checkInDue, checkInMissed: checkInMissed ?? this.checkInMissed,
      );
}

/// Owns everything that happens to the GPS stream during a journey: filtering, route progress, next
/// manoeuvre, ETA, deviation detection, rerouting and check-in reminders. UI widgets only read it.
/// It lives for the whole app session (it is created from the shell), so reminders and deviation
/// checks keep working whichever screen is open.
class NavigationController extends Notifier<NavState> {
  final _filter = GpsFilter();
  final _det = DeviationDetector(
    thresholdM: NavConfig.deviationThresholdM,
    requiredConsecutive: NavConfig.deviationConsecutiveFixes,
    maxAccuracyM: NavConfig.deviationMaxAccuracyM,
  );
  NavigationEngine? _engine;
  Timer? _ticker;
  int _hint = 0, _rerouteSeq = 0;
  DateTime? _snoozeUntil, _lastSaved;
  bool _streamError = false, _dueNotified = false, _checkInBusy = false;
  int _nearCount = 0;
  DateTime? _nearSince, _startedAt;

  @override
  NavState build() {
    ref.onDispose(() => _ticker?.cancel());
    ref.listen<Journey?>(activeJourneyProvider, (prev, next) {
      if (next == null) {
        _stop();
      } else if (prev?.id != next.id) {
        _begin(next);
      }
    });
    ref.listen<RouteOption?>(selectedRouteProvider, (_, r) => _setRoute(r));
    ref.listen<AsyncValue<Position>>(livePositionProvider, (_, next) {
      _streamError = next.hasError;
      final p = next.valueOrNull;
      if (p != null && !next.hasError) _onPosition(p);
    });
    final j = ref.read(activeJourneyProvider);
    if (j != null) Future.microtask(() => _begin(j));
    return const NavState();
  }

  // ---------- lifecycle ----------
  void _begin(Journey j) {
    _filter.reset();
    _det.reset();
    _hint = 0;
    _snoozeUntil = null;
    _dueNotified = false;
    _rerouteSeq++;
    _engine = null;
    _nearCount = 0;
    _nearSince = null;
    _startedAt = DateTime.now();
    state = NavState(active: true, nextCheckIn: DateTime.now().add(Duration(minutes: j.checkInMinutes)));
    _setRoute(ref.read(selectedRouteProvider));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _rerouteSeq++;
    _engine = null;
    _filter.reset();
    _det.reset();
    state = const NavState();
  }

  void _setRoute(RouteOption? r) {
    if (!state.active) return;
    _hint = 0;
    _nearCount = 0;
    _nearSince = null;
    _det.reset();
    _engine = (r == null || r.path.length < 2) ? null : NavigationEngine(r);
    state = state.copyWith(
      deviated: false, arrived: false, arrivalDismissed: false, routeHasSteps: _engine?.hasSteps ?? false,
      next: null, risk: null, remainingM: null, fraction: null, eta: null,
    );
    final f = state.fix;
    if (f != null) _progress(f);
  }

  // ---------- GPS ----------
  void _onPosition(Position p) {
    if (!state.active) return;
    final now = DateTime.now();
    final res = _filter.update(GeoPoint(p.latitude, p.longitude), p.accuracy, now, deviceSpeedMps: p.speed, deviceHeadingDeg: p.heading);
    if (res.verdict != FixVerdict.accepted) {
      if (res.verdict == FixVerdict.rejectedAccuracy) state = state.copyWith(rawAccuracyM: p.accuracy, gps: GpsStatus.poor);
      return;
    }
    final fix = res.fix!;
    final last = _lastSaved;
    if (last == null || now.difference(last) > const Duration(seconds: 5)) {
      _lastSaved = now;
      LocationService.save(ref.read(sharedPrefsProvider), fix.point);
    }
    state = state.copyWith(fix: fix, fixAt: now, rawAccuracyM: p.accuracy, gps: GpsStatus.good, travelledM: _filter.distanceTravelledM);
    _progress(fix);
  }

  /// Arrival needs several consecutive accurate fixes near the destination (or ~15 s spent there),
  /// never a single reading and never just "routing says 0 m". It latches once, so exactly one
  /// arrival prompt and one notification are produced.
  void _progress(FilteredFix fix) {
    final e = _engine;
    if (e == null || !e.usable) return;
    final m = e.geometry.match(fix.point, hintSegment: _hint);
    if (m == null) return;
    _hint = m.segment;
    final remaining = (e.geometry.totalM - m.alongM).clamp(0.0, e.geometry.totalM).toDouble();

    if (state.arrived) {
      // After arrival: no turn prompts, no ETA, no risk look-ahead.
      state = state.copyWith(remainingM: remaining, fraction: 1.0, next: null, risk: null, eta: null, etaBasis: '');
      return;
    }

    final near = remaining <= NavConfig.arrivalRadiusM && fix.accuracyM <= NavConfig.arrivalMaxAccuracyM;
    if (near) {
      _nearCount++;
      _nearSince ??= DateTime.now();
    } else {
      _nearCount = 0;
      _nearSince = null;
    }
    if (near && _nearCount >= NavConfig.arrivalConsecutiveFixes) {
      _latchArrival(remaining);
      return;
    }

    final eta = e.eta(remaining, _filter.averageMovingSpeedMps);
    state = state.copyWith(
      remainingM: remaining,
      fraction: (m.alongM / e.geometry.totalM).clamp(0.0, 1.0).toDouble(),
      next: state.paused ? null : e.nextStep(m.alongM),
      risk: e.upcomingRisk(m.alongM),
      eta: eta == null ? null : DateTime.now().add(eta.remaining),
      etaBasis: eta?.basis ?? '',
    );
    _checkDeviation(fix);
  }

  void _latchArrival(double remaining) {
    if (state.arrived) return;
    state = state.copyWith(arrived: true, arrivalDismissed: false, remainingM: remaining, fraction: 1.0, next: null, risk: null, eta: null, etaBasis: '', deviated: false);
    NotificationService.instance.show(3, 'You have reached your destination', 'Open RouteShield to confirm you are safe.');
  }

  /// "Continue tracking": hides the arrival card but keeps the journey (and tracking) active.
  void continueTracking() => state = state.copyWith(arrivalDismissed: true);

  /// Snapshot for the summary dialog; call BEFORE the journey is finished (the state resets after).
  JourneySummary summary(String destination, {required bool cancelled}) => JourneySummary(
      destination, DateTime.now().difference(_startedAt ?? DateTime.now()), state.travelledM, state.arrived, cancelled);

  void _checkDeviation(FilteredFix fix) {
    final path = _engine?.route.path;
    if (path == null || state.paused || state.arrived) return;
    final flagged = _det.update(fix.point, fix.accuracyM, path);
    if (state.deviated) {
      // Back on the route: clear the warning by itself.
      if (fix.accuracyM <= NavConfig.deviationMaxAccuracyM && distanceToPathMeters(fix.point, path) < NavConfig.deviationThresholdM * 0.5) {
        _det.reset();
        state = state.copyWith(deviated: false, proposal: null, rerouteMessage: null);
      }
      return;
    }
    final snoozed = _snoozeUntil != null && DateTime.now().isBefore(_snoozeUntil!);
    if (flagged && !snoozed) {
      state = state.copyWith(deviated: true);
      NotificationService.instance.show(2, 'You may be off route', 'Open RouteShield to recalculate or continue.');
    }
  }

  void _tick() {
    if (!state.active) return;
    final now = DateTime.now();
    final profile = ref.read(survivalProfileProvider);
    final quietAfter = _max(NavConfig.weakAfter, profile.locationInterval * 2);

    final access = ref.read(locationAccessProvider).valueOrNull;
    GpsStatus gps;
    if (_streamError || (access != null && access != LocationAccess.granted)) {
      gps = GpsStatus.unavailable;
    } else if (state.fixAt == null) {
      gps = state.gps == GpsStatus.poor ? GpsStatus.poor : GpsStatus.waiting;
    } else if (now.difference(state.fixAt!) > quietAfter) {
      gps = state.gps == GpsStatus.poor ? GpsStatus.poor : GpsStatus.quiet;
    } else {
      gps = GpsStatus.good;
    }

    if (!state.arrived && _nearSince != null && now.difference(_nearSince!) >= NavConfig.arrivalDwell && state.fix != null) {
      _latchArrival(state.remainingM ?? 0);
    }

    final nc = state.nextCheckIn;
    final due = nc != null && now.isAfter(nc);
    final missed = nc != null && now.isAfter(nc.add(NavConfig.checkInGrace));
    if (due && !_dueNotified) {
      _dueNotified = true;
      NotificationService.instance.show(1, 'Check-in due', 'Tap to confirm you are okay.');
    }
    if (gps != state.gps || due != state.checkInDue || missed != state.checkInMissed) {
      state = state.copyWith(gps: gps, checkInDue: due, checkInMissed: missed);
    }
  }

  Duration _max(Duration a, Duration b) => a > b ? a : b;

  // ---------- user actions ----------
  /// Pause: stops turn prompts and deviation alerts (e.g. a planned stop). GPS tracking and
  /// check-in reminders deliberately continue: this is a safety app.
  void pause() {
    if (!state.active || state.paused) return;
    _det.reset();
    state = state.copyWith(paused: true, deviated: false, next: null);
  }

  void resume() {
    if (!state.active || !state.paused) return;
    state = state.copyWith(paused: false);
    final f = state.fix;
    if (f != null) _progress(f);
  }

  void dismissDeviation() {
    _det.reset();
    _snoozeUntil = DateTime.now().add(NavConfig.deviationSnooze);
    state = state.copyWith(deviated: false, proposal: null, rerouteMessage: null);
  }

  /// Returns null on success or a message for the UI.
  Future<String?> checkIn() async {
    final j = ref.read(activeJourneyProvider);
    if (j == null || _checkInBusy) return null;
    _checkInBusy = true;
    try {
      await ref.read(repositoryProvider).checkIn(j.id);
      _dueNotified = false;
      state = state.copyWith(nextCheckIn: DateTime.now().add(Duration(minutes: j.checkInMinutes)), checkInDue: false, checkInMissed: false);
      return null;
    } catch (e) {
      return 'Check-in could not be saved: $e';
    } finally {
      _checkInBusy = false;
    }
  }

  /// Asks the routing backend for new routes from the CURRENT filtered GPS position to the same
  /// destination. Nothing changes until the user accepts the proposal. A stale or cancelled
  /// response is discarded.
  Future<void> requestReroute() async {
    final j = ref.read(activeJourneyProvider);
    final route = ref.read(selectedRouteProvider);
    final fix = state.fix;
    if (j == null || route == null || route.path.length < 2 || state.rerouting) return;
    if (fix == null) {
      state = state.copyWith(rerouteMessage: 'Waiting for a reliable GPS fix before recalculating.');
      return;
    }
    if (ref.read(apiClientProvider).token == 'demo') {
      state = state.copyWith(rerouteMessage: 'Recalculating needs the RouteShield server. Demo mode only has sample routes.');
      return;
    }
    final seq = ++_rerouteSeq;
    state = state.copyWith(rerouting: true, rerouteMessage: null, proposal: null);
    try {
      final dest = Destination(j.destination, route.path.last);
      final list = await ref.read(repositoryProvider).fetchRoutes(fix.point, dest);
      if (seq != _rerouteSeq || !state.active) return; // superseded or journey ended
      final usable = list.where((r) => !r.isDemo && r.path.length >= 2).toList();
      if (usable.isEmpty) {
        state = state.copyWith(rerouting: false, rerouteMessage: 'No new route was returned. Your current route is unchanged.');
        return;
      }
      final pick = usable.firstWhere((r) => r.label == route.label, orElse: () => usable.firstWhere((r) => r.recommended, orElse: () => usable.first));
      state = state.copyWith(rerouting: false, proposal: RerouteProposal(pick, DateTime.now()));
    } catch (e) {
      if (seq != _rerouteSeq) return;
      state = state.copyWith(rerouting: false, rerouteMessage: 'Could not recalculate: $e. Your current route is unchanged.');
    }
  }

  void acceptReroute() {
    final p = state.proposal;
    if (p == null) return;
    state = state.copyWith(proposal: null, rerouteMessage: null);
    ref.read(selectedRouteProvider.notifier).state = p.candidate; // triggers _setRoute
  }

  void discardReroute() => state = state.copyWith(proposal: null, rerouteMessage: null);
}

final navigationProvider = NotifierProvider<NavigationController, NavState>(NavigationController.new);
