import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/location_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final battery = ref.watch(batteryProvider);
    final survival = ref.watch(survivalModeProvider);
    final journey = ref.watch(activeJourneyProvider);
    final contacts = ref.watch(contactsProvider);
    final level = battery.valueOrNull;
    final low = level != null && level <= AppConfig.lowBatteryThreshold;
    final active = survival || low;
    final last = LocationService.load(ref.read(sharedPrefsProvider));
    return PageScaffold(
      title: 'Low-Battery Mode',
      child: ListView(padding: pagePadding, children: [
        RsCard(
          color: low ? RS.red : null,
          child: Row(children: [
            Icon(low ? Icons.battery_alert : Icons.battery_std, size: 40, color: low ? RS.redText : Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(level == null ? 'Battery level unavailable' : 'Battery $level%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: low ? RS.redText : null)),
              Text(low ? 'Low. Survival Mode is applied automatically.' : 'Reading from your device', style: TextStyle(color: low ? RS.redText : null)),
            ])),
          ]),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero, value: active,
          title: const Text('Survival Mode', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Fewer, lower-accuracy location updates and less network activity.'),
          onChanged: low ? null : (v) {
            ref.read(survivalModeProvider.notifier).state = v;
            ref.read(sharedPrefsProvider).setBool('survival', v);
          },
        ),
        if (active)
          RsCard(color: RS.amber, child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.gps_off, color: RS.amberText),
            SizedBox(width: 10),
            Expanded(child: Text('Live tracking is reduced. Your last recorded location is shown below, not your live position.', style: TextStyle(color: RS.amberText, fontWeight: FontWeight.w600))),
          ])),
        const SectionTitle('Last recorded location'),
        RsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(last == null ? 'No location recorded yet.' : '${last.point.lat.toStringAsFixed(5)}, ${last.point.lng.toStringAsFixed(5)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (last != null) Text('Recorded ${DateFormat('d MMM, HH:mm:ss').format(last.at)} (${DateTime.now().difference(last.at).inMinutes} min ago)'),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _updating ? null : _refreshLocation, icon: _updating ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location), label: const Text('Record location once')),
        ])),
        if (journey != null) ...[
          const SectionTitle('Journey essentials (saved on this phone)'),
          RsCard(child: Text('To ${journey.destination}\nExpected arrival ${DateFormat('HH:mm').format(journey.expectedArrival)}', style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4))),
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
      ]),
    );
  }
}
