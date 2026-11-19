import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);
    final fmt = DateFormat('d MMM yyyy, HH:mm');
    return PageScaffold(
      title: 'Journey history',
      child: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(historyProvider)),
        data: (list) => list.isEmpty
            ? const EmptyView(icon: Icons.history, title: 'No journeys yet', message: 'Completed and cancelled journeys appear here.')
            : ListView(padding: pagePadding, children: [
                const DemoBanner(),
                for (final Journey j in list)
                  RsCard(child: Row(children: [
                    Icon(switch (j.status) { 'completed' => Icons.check_circle_outline, 'cancelled' => Icons.cancel_outlined, _ => Icons.navigation_outlined }),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(j.destination, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${fmt.format(j.startedAt)}\nStatus: ${j.status}${j.isDemo ? ' (demo)' : ''}'),
                    ])),
                  ])),
              ]),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final fmt = DateFormat('d MMM, HH:mm');
    return PageScaffold(
      title: 'Notifications',
      child: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(notificationsProvider)),
        data: (list) => list.isEmpty
            ? const EmptyView(icon: Icons.notifications_none, title: 'All caught up', message: 'Check-in reminders and alerts will appear here.')
            : ListView(padding: pagePadding, children: [
                for (final AppNotification n in list)
                  RsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(n.body),
                    const SizedBox(height: 4),
                    Text(fmt.format(n.at), style: const TextStyle(fontSize: 12.5)),
                  ])),
              ]),
      ),
    );
  }
}
