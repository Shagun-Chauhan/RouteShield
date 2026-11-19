import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authProvider).name ?? 'there';
    final battery = ref.watch(batteryProvider);
    final journey = ref.watch(activeJourneyProvider);
    final cs = Theme.of(context).colorScheme;
    final tiles = <(IconData, String, String)>[
      (Icons.local_hospital_outlined, 'Safe Havens', '/havens'),
      (Icons.checklist_rtl, 'Safety Plan', '/plan'),
      (Icons.battery_saver_outlined, 'Low-Battery', '/battery'),
      (Icons.group_outlined, 'Contacts', '/contacts'),
      (Icons.phone_in_talk_outlined, 'Simulated call', '/call'),
      (Icons.history, 'History', '/history'),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: pagePadding, children: [
          Row(children: [
            Expanded(child: Text('Hello, $name', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(tooltip: 'Notifications', onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_none)),
          ]),
          const SizedBox(height: 8),
          const DemoBanner(),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(gradient: RS.gradient, borderRadius: BorderRadius.circular(24), boxShadow: RS.shadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.alt_route, color: Colors.white, size: 32),
              const SizedBox(height: 14),
              const Text('Plan a Safer Journey', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Compare routes by estimated risk, confidence and time.', style: TextStyle(color: Colors.white, fontSize: 14.5)),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: RS.navy),
                onPressed: () => context.push('/search'),
                icon: const Icon(Icons.search),
                label: const Text('Where to?'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (journey != null)
            RsCard(
              color: RS.amber,
              onTap: () => context.push('/journey'),
              child: Row(children: [
                const Icon(Icons.navigation_outlined, color: RS.amberText),
                const SizedBox(width: 12),
                Expanded(child: Text('Journey to ${journey.destination} in progress. Tap to open.', style: const TextStyle(color: RS.amberText, fontWeight: FontWeight.w700))),
                const Icon(Icons.chevron_right, color: RS.amberText),
              ]),
            ),
          battery.when(
            data: (b) => RsCard(
              onTap: () => context.push('/battery'),
              child: Row(children: [
                Icon(b <= AppConfig.lowBatteryThreshold ? Icons.battery_alert : Icons.battery_full, color: b <= AppConfig.lowBatteryThreshold ? RS.redText : cs.secondary),
                const SizedBox(width: 12),
                Expanded(child: Text(b <= AppConfig.lowBatteryThreshold ? 'Battery $b%. Consider Low-Battery Survival Mode.' : 'Battery $b%', style: const TextStyle(fontWeight: FontWeight.w600))),
                const Icon(Icons.chevron_right),
              ]),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SectionTitle('Tools'),
          GridView.count(
            crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.95,
            children: [
              for (final t in tiles)
                InkWell(
                  borderRadius: BorderRadius.circular(RS.radius),
                  onTap: () => context.push(t.$3),
                  child: Ink(
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(RS.radius), border: Border.all(color: cs.outline), boxShadow: RS.shadow),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(t.$1, size: 28, color: cs.secondary),
                      const SizedBox(height: 8),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(t.$2, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('RouteShield supports your decisions. It cannot guarantee safety or replace emergency services. In danger, call 112.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        ]),
      ),
    );
  }
}
