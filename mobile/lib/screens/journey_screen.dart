import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/navigation_providers.dart';
import '../providers/providers.dart';
import '../services/journey_service.dart';
import '../widgets/map/nav_panels.dart' show RerouteCard;
import '../services/live_location.dart';
import '../services/location_service.dart';
import '../widgets/common.dart';

class ActiveJourneyScreen extends ConsumerStatefulWidget {
  const ActiveJourneyScreen({super.key});
  @override
  ConsumerState<ActiveJourneyScreen> createState() => _JourneyState();
}

class _JourneyState extends ConsumerState<ActiveJourneyScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (mounted) setState(() {}); // refresh countdown; reminders themselves run in NavigationController
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _checkIn(Journey j) async {
    final err = await ref.read(navigationProvider.notifier).checkIn();
    if (!mounted) return;
    snack(context, err ?? 'Checked in. Next reminder in ${j.checkInMinutes} min.');
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
    final where = last == null ? 'Location unavailable.' : 'Last location (${DateFormat('HH:mm').format(last.at)}): https://www.openstreetmap.org/?mlat=${last.point.lat}&mlon=${last.point.lng}#map=17/${last.point.lat}/${last.point.lng}';
    final body = missed ? 'I missed a check-in on my RouteShield journey to ${j.destination}. I may be fine, but please check on me. $where' : 'My RouteShield journey to ${j.destination}. $where';
    final uri = Uri(scheme: 'sms', path: contacts.first.phone, queryParameters: {'body': body});
    final launched = await launchUrl(uri);
    if (!launched && mounted) snack(context, 'Could not open the messaging app.');
  }

  Future<void> _finish(Journey j, {bool cancel = false}) async {
    final err = await ref.read(journeyServiceProvider).finish(j, cancel: cancel);
    if (!mounted) return;
    if (err != null) {
      snack(context, err);
      return;
    }
    snack(context, cancel ? 'Journey cancelled.' : 'Journey completed. Glad you arrived.');
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navigationProvider);
    final posState = ref.watch(livePositionProvider);
    final access = ref.watch(locationAccessProvider).valueOrNull;
    final saver = ref.watch(survivalModeProvider);
    final gpsOk = (access == null || access == LocationAccess.granted) && !posState.hasError;
    final j = ref.watch(activeJourneyProvider);
    if (j == null) {
      return PageScaffold(title: 'Journey', child: EmptyView(icon: Icons.navigation_outlined, title: 'No active journey', message: 'Plan a journey to see live status here.', action: FilledButton(onPressed: () => context.go('/search'), child: const Text('Plan a journey'))));
    }
    final now = DateTime.now();
    final remaining = (nav.nextCheckIn ?? now).difference(now);
    final due = nav.checkInDue;
    final missed = nav.checkInMissed;
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
        const RerouteCard(),
        RsCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(gpsOk ? Icons.gps_fixed : Icons.gps_off), const SizedBox(width: 8), Expanded(child: Text(gpsOk ? (saver ? 'Battery saver: fewer location updates' : 'Live tracking on') : 'Live tracking unavailable', style: const TextStyle(fontWeight: FontWeight.w700)))]),
            const SizedBox(height: 6),
            Text(last == null ? 'No location recorded yet.' : 'Last recorded location: ${DateFormat('HH:mm:ss').format(last.at)}${nav.fixAt == null ? ' (from earlier)' : ''}'),
            if (!gpsOk) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Turn on Location and allow permission to enable tracking.')),
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
