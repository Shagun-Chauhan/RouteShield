import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/location_service.dart';
import '../services/safety_plan.dart';
import '../widgets/common.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});
  @override
  ConsumerState<PlanScreen> createState() => _PlanState();
}

class _PlanState extends ConsumerState<PlanScreen> {
  Situation _s = Situation.lowBattery;

  @override
  Widget build(BuildContext context) {
    final battery = ref.watch(batteryProvider).valueOrNull;
    final hasContacts = (ref.watch(contactsProvider).valueOrNull ?? const []).isNotEmpty;
    final last = LocationService.load(ref.read(sharedPrefsProvider));
    final steps = compilePlan(_s, hasContacts: hasContacts, batteryPct: battery, lastLocationAt: last?.at);
    return PageScaffold(
      title: 'Safety Plan',
      child: ListView(padding: pagePadding, children: [
        const Text('What is happening?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in Situation.values) ChoiceChip(label: Text(situationLabel(s)), selected: _s == s, onSelected: (_) => setState(() => _s = s)),
        ]),
        const SizedBox(height: 16),
        for (var i = 0; i < steps.length; i++)
          RsCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(steps[i].title, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text(steps[i].detail)])),
          ])),
        const SizedBox(height: 4),
        const Text('This plan follows fixed rules. It is guidance, not a guarantee. In immediate danger call 112.', style: TextStyle(fontSize: 12.5)),
      ]),
    );
  }
}
