import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/survival_providers.dart' show survivalProfileProvider, survivalControllerProvider, batterySnapshotProvider;
import '../../services/survival_policy.dart';
import '../common.dart';
import 'map_widgets.dart';

/// Compact replacement for the old full-width battery banner. Visible only while survival mode is on.
class SurvivalChip extends ConsumerWidget {
  const SurvivalChip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(survivalProfileProvider.select((p) => p.survival))) return const SizedBox.shrink();
    final level = ref.watch(batterySnapshotProvider).valueOrNull?.level;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: 'Battery survival mode is on. Tap for status.',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _SurvivalSheet()),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF7A4B00).withAlpha(90))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.battery_saver, size: 18, color: Color(0xFF7A4B00)),
                  const SizedBox(width: 6),
                  Text('Battery saver${level == null ? '' : '  $level%'}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7A4B00), fontSize: 13)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SurvivalSheet extends ConsumerWidget {
  const _SurvivalSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(survivalProfileProvider);
    final ui = ref.watch(survivalControllerProvider);
    final level = ref.watch(batterySnapshotProvider).valueOrNull?.level;
    final cs = Theme.of(context).colorScheme;
    final src = switch (ui.policy.source) {
      SurvivalSource.auto => 'Turned on automatically (low battery)',
      SurvivalSource.manual => 'Turned on by you',
      SurvivalSource.none => 'Off',
    };
    Widget row(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, size: 18), const SizedBox(width: 10), Expanded(child: Text(t))]),
        );
    final alert = ui.latest;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text('Battery survival mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('$src${level == null ? '' : '  ·  battery $level%'}', style: TextStyle(color: cs.onSurfaceVariant)),
        const SectionTitle('Still running'),
        row(Icons.gps_fixed, 'GPS tracking, at a lower rate: about every ${profile.locationInterval.inSeconds >= 60 ? '${profile.locationInterval.inMinutes} min' : '${profile.locationInterval.inSeconds} s'} or when you move 50 m.'),
        row(Icons.shield_outlined, 'Journey state, check-in reminders, deviation checks and SOS.'),
        row(Icons.history, 'Your last known location and its timestamp are kept.'),
        const SectionTitle('Paused'),
        row(Icons.store_mall_directory_outlined, 'Automatic refresh of nearby places.'),
        row(Icons.sync_disabled, 'Background map refresh and other non-essential requests.'),
        if (alert != null) ...[
          const SectionTitle('Last low-battery alert to contacts'),
          Text(alert.detail.isEmpty ? alert.status.name : alert.detail),
        ],
        const SizedBox(height: 8),
        Text('Android may still limit background work on some phones. Keep RouteShield excluded from battery optimisation for best tracking.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
