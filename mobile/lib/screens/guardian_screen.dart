import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class GuardianScreen extends ConsumerWidget {
  const GuardianScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = ref.watch(activeJourneyProvider);
    final mins = ref.watch(checkInMinutesProvider);
    final contacts = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Journey Guardian')),
      body: SafeArea(
        child: ListView(padding: pagePadding, children: [
          const DemoBanner(),
          if (j == null)
            RsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('No active journey', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 6),
              const Text('Start a journey to set check-ins and choose who can be alerted.'),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => context.push('/search'), child: const Text('Plan a journey')),
            ]))
          else
            RsCard(onTap: () => context.push('/journey'), child: Row(children: [
              const Icon(Icons.navigation_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text('To ${j.destination}\nArrival around ${DateFormat('HH:mm').format(j.expectedArrival)}', style: const TextStyle(fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right),
            ])),
          const SectionTitle('Default check-in reminder'),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 10, label: Text('10 min')), ButtonSegment(value: 15, label: Text('15 min')), ButtonSegment(value: 30, label: Text('30 min'))],
            selected: {mins},
            onSelectionChanged: (s) {
              ref.read(checkInMinutesProvider.notifier).state = s.first;
              ref.read(sharedPrefsProvider).setInt('checkin', s.first);
            },
          ),
          const SizedBox(height: 16),
          RsCard(
            onTap: () => context.push('/contacts'),
            child: Row(children: [
              const Icon(Icons.group_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text(contacts.when(data: (l) => l.isEmpty ? 'No trusted contacts yet' : '${l.length} trusted contact(s)', loading: () => 'Loading contacts...', error: (_, __) => 'Contacts unavailable'), style: const TextStyle(fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right),
            ]),
          ),
          const SectionTitle('How it works'),
          const RsCard(child: Text('1. You get a reminder at each check-in time.\n2. If you do not respond, you see a "missed check-in" prompt. It is not treated as an emergency.\n3. You decide whether to alert contacts. Only contacts who agreed to receive your location are offered.\n4. Alerts open your messaging app so you can review and send. Location sharing needs a working connection.', style: TextStyle(height: 1.5))),
        ]),
      ),
    );
  }
}
