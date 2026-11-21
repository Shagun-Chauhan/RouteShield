import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:routeshield/providers/survival_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/emergency_alert.dart';
import '../services/location_service.dart';
import '../services/survival_policy.dart';
import '../widgets/common.dart';

class BatteryScreen extends ConsumerStatefulWidget {
  const BatteryScreen({super.key});
  @override
  ConsumerState<BatteryScreen> createState() => _BatteryState();
}

class _BatteryState extends ConsumerState<BatteryScreen> {
  bool _updating = false;

  Future<void> _refreshLocation() async {
    setState(() => _updating = true);
    final p = await LocationService.current();
    if (p != null) await LocationService.save(ref.read(sharedPrefsProvider), p);
    if (!mounted) return;
    setState(() => _updating = false);
    if (p == null) snack(context, 'Could not get a location. Showing the last recorded one.');
  }

  Future<void> _sendViaMessagingApp(EmergencyAlertRecord r, List<TrustedContact> contacts, int threshold) async {
    final body = AlertMessage.compose(
      name: ref.read(authProvider).name,
      battery: r.battery,
      threshold: threshold,
      now: DateTime.now(),
      fix: r.fix,
    );
    final to = contacts.map((c) => c.phone.replaceAll(RegExp(r'[^0-9+]'), '')).join(',');
    final ok = await launchUrl(Uri.parse('sms:$to?body=${Uri.encodeComponent(body)}'));
    if (ok) {
      await ref.read(survivalControllerProvider.notifier).markSmsOpened(r.id);
    } else if (mounted) {
      snack(context, 'No messaging app could be opened.');
    }
  }

  static String _chargeText(BatteryState s) => switch (s) {
        BatteryState.charging => 'Charging',
        BatteryState.full => 'Plugged in, fully charged',
        BatteryState.connectedNotCharging => 'Plugged in, not charging',
        BatteryState.discharging => 'On battery (discharging)',
        _ => 'Charging state unknown',
      };

  static String _every(Duration? d) =>
      d == null ? 'Paused' : (d.inSeconds < 60 ? 'Every ${d.inSeconds} s' : 'Every ${d.inMinutes} min');

  Widget _line(IconData icon, String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: color))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final b = ref.watch(batterySnapshotProvider).valueOrNull;
    final ui = ref.watch(survivalControllerProvider);
    final cfg = ref.watch(survivalConfigProvider);
    final profile = ref.watch(survivalProfileProvider);
    final journey = ref.watch(activeJourneyProvider);
    final contacts = ref.watch(contactsProvider);
    final level = b?.level;
    final critical = level != null && level <= cfg.activateAt;
    final low = level != null && level <= cfg.warnAt;
    final active = ui.policy.active;
    final last = LocationService.load(ref.read(sharedPrefsProvider));
    final alert = ui.latest;

    final Color? heroBg = critical ? RS.red : (active ? RS.amber : null);
    final Color? heroFg = critical ? RS.redText : (active ? RS.amberText : null);
    final headline = critical
        ? 'Critical battery'
        : active
            ? 'Survival Mode active'
            : low
                ? 'Low battery'
                : 'Normal mode';

    final modeNote = switch (ui.policy.source) {
      SurvivalSource.auto => 'Turned on automatically because the battery is low.',
      SurvivalSource.manual => 'Turned on by you. It stays on until you turn it off.',
      SurvivalSource.none => ui.policy.suppressed
          ? 'You turned it off while the battery was low. Automatic activation resumes after the battery passes ${cfg.recoverAt}%.'
          : 'Starts automatically at ${cfg.activateAt}% or below' +
              (cfg.autoRecover ? ' and turns off above ${cfg.recoverAt}%.' : '.'),
    };

    return PageScaffold(
      title: 'Low-Battery Mode',
      child: ListView(padding: pagePadding, children: [
        // ---- Status ----
        RsCard(
          color: heroBg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(critical ? Icons.battery_alert : (b?.isPlugged == true ? Icons.battery_charging_full : Icons.battery_std),
                  size: 40, color: heroFg ?? Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(level == null ? 'Battery level unavailable' : 'Battery $level%',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: heroFg)),
                  Text(headline, style: TextStyle(fontWeight: FontWeight.w600, color: heroFg)),
                ]),
              ),
            ]),
            if (level != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: level / 100, minHeight: 6),
            ],
            const SizedBox(height: 10),
            if (b != null) _line(Icons.power, 'Power', _chargeText(b.state), color: heroFg),
            if (b?.systemSaverOn != null)
              _line(Icons.battery_saver, 'Android Battery Saver', b!.systemSaverOn! ? 'On' : 'Off', color: heroFg),
          ]),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: active,
          title: const Text('Survival Mode', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(modeNote),
          onChanged: (v) => ref.read(survivalControllerProvider.notifier).setManual(v),
        ),

        // ---- Rules ----
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Automatic rules: on at ${cfg.activateAt}%, off above ${cfg.recoverAt}%',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          children: [
            Align(alignment: Alignment.centerLeft, child: Text('Activate at ${cfg.activateAt}% or below')),
            Slider(
              min: 5, max: 50, divisions: 45, value: cfg.activateAt.toDouble(), label: '${cfg.activateAt}%',
              onChanged: (v) => ref.read(survivalConfigProvider.notifier).state = cfg.copyWith(activateAt: v.round()),
              onChangeEnd: (_) => ref.read(survivalControllerProvider.notifier).updateConfig(ref.read(survivalConfigProvider)),
            ),
            Align(alignment: Alignment.centerLeft, child: Text('Recover above ${cfg.recoverAt}%')),
            Slider(
              min: (cfg.activateAt + 5).toDouble(), max: 100, divisions: 95 - cfg.activateAt,
              value: cfg.recoverAt.toDouble(), label: '${cfg.recoverAt}%',
              onChanged: (v) => ref.read(survivalConfigProvider.notifier).state = cfg.copyWith(recoverAt: v.round()),
              onChangeEnd: (_) => ref.read(survivalControllerProvider.notifier).updateConfig(ref.read(survivalConfigProvider)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, value: cfg.autoRecover,
              title: const Text('Turn off automatically when recovered'),
              subtitle: const Text('Never turns off a mode you switched on yourself.'),
              onChanged: (v) => ref.read(survivalControllerProvider.notifier).updateConfig(cfg.copyWith(autoRecover: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, value: cfg.notifyContacts,
              title: const Text('Alert trusted contacts at the critical level'),
              onChanged: (v) => ref.read(survivalControllerProvider.notifier).updateConfig(cfg.copyWith(notifyContacts: v)),
            ),
          ],
        ),

        // ---- Background activity ----
        const SectionTitle('Background activity'),
        RsCard(child: Column(children: [
          _line(Icons.lock_outline, 'Battery monitoring', 'Always on'),
          _line(Icons.sos, 'SOS and emergency contacts', 'Always on'),
          _line(Icons.place_outlined, 'Last-known location', 'Always on'),
          _line(Icons.notifications_active_outlined, 'Low-battery contact alert', cfg.notifyContacts ? 'Always on' : 'Off (your setting)'),
          const Divider(),
          _line(Icons.my_location, 'Location updates', _every(profile.locationInterval)),
          _line(Icons.sync, 'Data sync', _every(profile.syncInterval)),
          _line(Icons.map_outlined, 'Map refresh', _every(profile.mapRefreshInterval)),
          _line(Icons.animation, 'Animations and media prefetch', profile.animationsEnabled ? 'Normal' : 'Reduced'),
        ])),
        if (active)
          RsCard(color: RS.amber, child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.gps_off, color: RS.amberText),
            SizedBox(width: 10),
            Expanded(child: Text('Live tracking is reduced. Your last recorded location is shown below, not your live position.',
                style: TextStyle(color: RS.amberText, fontWeight: FontWeight.w600))),
          ])),

        // ---- Contact alert ----
        const SectionTitle('Trusted-contact alert'),
        _alertCard(alert, cfg.activateAt, contacts.valueOrNull ?? const []),

        // ---- Location ----
        const SectionTitle('Last recorded location'),
        RsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(last == null ? 'No location recorded yet.' : '${last.point.lat.toStringAsFixed(5)}, ${last.point.lng.toStringAsFixed(5)}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (last != null) ...[
            Text('Recorded ${DateFormat('d MMM, HH:mm:ss').format(last.at)} (${ageText(DateTime.now().difference(last.at))})'),
            if (DateTime.now().difference(last.at) > staleAfter)
              const Text('This may be out of date and may not be where you are now.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _updating ? null : _refreshLocation,
              icon: _updating ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
              label: const Text('Record location once'),
            ),
            if (last != null)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(LocationFix(lat: last.point.lat, lng: last.point.lng, at: last.at).osmLink),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open map'),
              ),
          ]),
        ])),

        if (journey != null) ...[
          const SectionTitle('Journey essentials (saved on this phone)'),
          RsCard(child: Text('To ${journey.destination}\nExpected arrival ${DateFormat('HH:mm').format(journey.expectedArrival)}',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4))),
        ],

        const SectionTitle('Trusted contacts'),
        contacts.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Contacts unavailable: $e'),
          data: (l) => l.isEmpty
              ? const Text('No trusted contacts saved.')
              : Column(children: [
                  for (final c in l)
                    RsCard(child: Row(children: [
                      Expanded(child: Text('${c.name}\n${c.phone}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      IconButton.filledTonal(tooltip: 'Call ${c.name}', onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.phone)), icon: const Icon(Icons.call)),
                    ])),
                ]),
        ),

        if (ui.history.length > 1) ...[
          const SectionTitle('Alert history'),
          RsCard(child: Column(children: [
            for (final r in ui.history.take(5))
              _line(Icons.history, DateFormat('d MMM, HH:mm').format(r.createdAt) + ' at ${r.battery}%', _statusLabel(r.status)),
          ])),
        ],
      ]),
    );
  }

  static String _statusLabel(AlertStatus s) => switch (s) {
        AlertStatus.queued => 'Pending',
        AlertStatus.accepted => 'Sent (accepted)',
        AlertStatus.partial => 'Partly sent',
        AlertStatus.failed => 'Failed',
        AlertStatus.noContacts => 'No contacts',
        AlertStatus.skipped => 'Not sent (demo)',
        AlertStatus.manualOpened => 'Opened in SMS app',
      };

  Widget _alertCard(EmergencyAlertRecord? a, int threshold, List<TrustedContact> contacts) {
    if (a == null) {
      return RsCard(child: Text(contacts.isEmpty
          ? 'No trusted contacts saved. Add contacts so RouteShield can alert them at $threshold%.'
          : 'No low-battery alert has been needed. ${contacts.length} contact(s) will be alerted at $threshold% or below.'));
    }
    final bad = a.status == AlertStatus.failed || a.status == AlertStatus.noContacts;
    final pending = a.status == AlertStatus.queued;
    final Color? bg = bad ? RS.red : (pending ? RS.amber : null);
    final Color? fg = bad ? RS.redText : (pending ? RS.amberText : null);
    final canRetry = bad || pending;
    return RsCard(
      color: bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_statusLabel(a.status), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: fg)),
        const SizedBox(height: 4),
        Text(a.detail, style: TextStyle(color: fg)),
        const SizedBox(height: 6),
        Text('Alert time ${DateFormat('d MMM, HH:mm').format(a.createdAt)}, battery ${a.battery}%', style: TextStyle(color: fg)),
        Text(
          a.fix == null
              ? 'No location was available to include.'
              : 'Location from ${DateFormat('d MMM, HH:mm').format(a.fix!.at)}${a.locationStale ? ' (out of date)' : ''}',
          style: TextStyle(color: fg),
        ),
        if (canRetry) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => ref.read(survivalControllerProvider.notifier).retryAlert(), child: const Text('Retry now')),
            if (contacts.isNotEmpty)
              OutlinedButton(onPressed: () => _sendViaMessagingApp(a, contacts, threshold), child: const Text('Send from messaging app')),
          ]),
        ],
      ]),
    );
  }
}
