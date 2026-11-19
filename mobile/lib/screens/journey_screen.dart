import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/deviation_detector.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../widgets/common.dart';

class ActiveJourneyScreen extends ConsumerStatefulWidget {
  const ActiveJourneyScreen({super.key});
  @override
  ConsumerState<ActiveJourneyScreen> createState() => _JourneyState();
}

class _JourneyState extends ConsumerState<ActiveJourneyScreen> {
  static const _grace = Duration(minutes: 5);
  final _det = DeviationDetector();
  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  late DateTime _nextCheckIn;
  bool _dueNotified = false, _deviated = false, _saver = false, _gpsOk = true;
  DateTime? _lastFix;

  @override
  void initState() {
    super.initState();
    final j = ref.read(activeJourneyProvider);
    _nextCheckIn = DateTime.now().add(Duration(minutes: j?.checkInMinutes ?? 15));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _startLocation();
  }

  Future<void> _startLocation() async {
    await _sub?.cancel();
    final ok = await LocationService.ensurePermission();
    if (!mounted) return;
    setState(() => _gpsOk = ok);
    if (!ok) return;
    final prefs = ref.read(sharedPrefsProvider);
    final path = ref.read(selectedRouteProvider)?.path ?? const <GeoPoint>[];
    _sub = LocationService.stream(saver: _saver).listen((pos) {
      final p = GeoPoint(pos.latitude, pos.longitude);
      LocationService.save(prefs, p);
      if (mounted) setState(() { _lastFix = DateTime.now(); _gpsOk = true; });
      if (path.isNotEmpty && !_deviated && _det.update(p, pos.accuracy, path)) {
        setState(() => _deviated = true);
        NotificationService.instance.show(2, 'You may be off route', 'Open RouteShield to review alternatives.');
      }
    }, onError: (_) {
      if (mounted) setState(() => _gpsOk = false);
    });
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    if (!_dueNotified && now.isAfter(_nextCheckIn)) {
      _dueNotified = true;
      NotificationService.instance.show(1, 'Check-in due', 'Tap to confirm you are okay.');
    }
    setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _checkIn(Journey j) async {
    await ref.read(repositoryProvider).checkIn(j.id);
    if (!mounted) return;
    setState(() { _nextCheckIn = DateTime.now().add(Duration(minutes: j.checkInMinutes)); _dueNotified = false; });
    snack(context, 'Checked in. Next reminder in ${j.checkInMinutes} min.');
  }

  /// Opens the SMS app pre-filled. RouteShield never sends anything without the user's confirmation.
  Future<void> _shareLocation(Journey j, {required bool missed}) async {
    final contacts = (await ref.read(repositoryProvider).contacts()).where((c) => j.contactIds.contains(c.id) && c.consentToShare).toList();
    if (!mounted) return;
    if (contacts.isEmpty) {
      snack(context, 'No selected contact has agreed to receive your location.');
      return;
    }
    final last = LocationService.load(ref.read(sharedPrefsProvider));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Share your location?'),
        content: Text('This opens a message to ${contacts.map((e) => e.name).join(', ')} with your last recorded location${last == null ? ' (none recorded yet)' : ' from ${DateFormat('HH:mm').format(last.at)}'}. You choose whether to send it.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Open message'))],
      ),
    );
    if (ok != true) return;
    final where = last == null ? 'Location unavailable.' : 'Last location (${DateFormat('HH:mm').format(last.at)}): https://maps.google.com/?q=${last.point.lat},${last.point.lng}';
    final body = missed ? 'I missed a check-in on my RouteShield journey to ${j.destination}. I may be fine, but please check on me. $where' : 'My RouteShield journey to ${j.destination}. $where';
    final uri = Uri(scheme: 'sms', path: contacts.first.phone, queryParameters: {'body': body});
    final launched = await launchUrl(uri);
    if (!launched && mounted) snack(context, 'Could not open the messaging app.');
  }

  Future<void> _finish(Journey j, {bool cancel = false}) async {
    await ref.read(repositoryProvider).completeJourney(j.id, cancelled: cancel);
    ref.read(activeJourneyProvider.notifier).state = null;
    ref.read(selectedRouteProvider.notifier).state = null;
    if (mounted) {
      snack(context, cancel ? 'Journey cancelled.' : 'Journey completed. Glad you arrived.');
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    void applySaver() {
      final low = (ref.read(batteryProvider).valueOrNull ?? 100) <= AppConfig.lowBatteryThreshold;
      final want = low || ref.read(survivalModeProvider);
      if (want != _saver) {
        _saver = want;
        _startLocation();
      }
    }

    ref.listen<AsyncValue<int>>(batteryProvider, (prev, next) => applySaver());
    ref.listen<bool>(survivalModeProvider, (prev, next) => applySaver());
    final j = ref.watch(activeJourneyProvider);
    if (j == null) {
      return PageScaffold(title: 'Journey', child: EmptyView(icon: Icons.navigation_outlined, title: 'No active journey', message: 'Plan a journey to see live status here.', action: FilledButton(onPressed: () => context.go('/search'), child: const Text('Plan a journey'))));
    }
    final now = DateTime.now();
    final remaining = _nextCheckIn.difference(now);
    final due = remaining.isNegative;
    final missed = due && now.isAfter(_nextCheckIn.add(_grace));
    String mmss(Duration d) => '${d.inMinutes.abs().toString().padLeft(2, '0')}:${(d.inSeconds.abs() % 60).toString().padLeft(2, '0')}';
    final last = LocationService.load(ref.read(sharedPrefsProvider));
    return PageScaffold(
      title: 'Active journey',
      child: ListView(padding: pagePadding, children: [
        const DemoBanner(),
        RsCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('To ${j.destination}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Expected arrival ${DateFormat('HH:mm').format(j.expectedArrival)}'),
            const SizedBox(height: 14),
            Row(children: [
              Icon(due ? Icons.notifications_active_outlined : Icons.timer_outlined),
              const SizedBox(width: 8),
              Text(due ? 'Check-in due (${mmss(remaining)} ago)' : 'Next check-in in ${mmss(remaining)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        if (due)
          RsCard(
            color: missed ? RS.red : RS.amber,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(missed ? 'Missed check-in' : 'Time to check in', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: missed ? RS.redText : RS.amberText)),
              const SizedBox(height: 4),
              Text(missed ? 'This is not treated as an emergency. If you are okay, check in. You decide whether contacts are alerted.' : 'Please confirm you are okay.', style: TextStyle(color: missed ? RS.redText : RS.amberText)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => _checkIn(j), child: const Text("I'm okay")),
              if (missed) ...[const SizedBox(height: 8), OutlinedButton(onPressed: () => _shareLocation(j, missed: true), child: const Text('Alert my contacts (asks first)'))],
            ]),
          )
        else
          FilledButton.icon(onPressed: () => _checkIn(j), icon: const Icon(Icons.check_circle_outline), label: const Text("Check in: I'm okay")),
        const SizedBox(height: 12),
        if (_deviated)
          RsCard(
            color: RS.amber,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('You appear to be off route', style: TextStyle(fontWeight: FontWeight.w800, color: RS.amberText, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Several recent location readings were away from your route. Detours are fine if intended.', style: TextStyle(color: RS.amberText)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => context.push('/routes', extra: j.destination), child: const Text('Recover route')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () { _det.reset(); setState(() => _deviated = false); }, child: const Text("I'm fine, continue")),
            ]),
          ),
        RsCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(_gpsOk ? Icons.gps_fixed : Icons.gps_off), const SizedBox(width: 8), Expanded(child: Text(_gpsOk ? (_saver ? 'Battery saver: fewer location updates' : 'Live tracking on') : 'Live tracking unavailable', style: const TextStyle(fontWeight: FontWeight.w700)))]),
            const SizedBox(height: 6),
            Text(last == null ? 'No location recorded yet.' : 'Last recorded location: ${DateFormat('HH:mm:ss').format(last.at)}${_lastFix == null ? ' (from earlier)' : ''}'),
            if (!_gpsOk) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Turn on Location and allow permission to enable tracking.')),
          ]),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(onPressed: () => _shareLocation(j, missed: false), icon: const Icon(Icons.share_location), label: const Text('Share last location')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => context.push('/havens'), icon: const Icon(Icons.local_hospital_outlined), label: const Text('Nearest safe havens')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => context.push('/plan'), icon: const Icon(Icons.checklist_rtl), label: const Text('Safety plan')),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => _finish(j), child: const Text("I've arrived: complete journey")),
        const SizedBox(height: 8),
        TextButton(onPressed: () => _finish(j, cancel: true), child: const Text('Cancel journey')),
      ]),
    );
  }
}
