import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class HavensScreen extends ConsumerStatefulWidget {
  const HavensScreen({super.key});
  @override
  ConsumerState<HavensScreen> createState() => _HavensState();
}

class _HavensState extends ConsumerState<HavensScreen> {
  String _filter = 'all';

  IconData _icon(String t) => switch (t) { 'hospital' => Icons.local_hospital_outlined, 'police' => Icons.local_police_outlined, _ => Icons.account_balance_outlined };
  String _dist(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(havensProvider);
    return PageScaffold(
      title: 'Safe Havens',
      child: async.when(
        loading: () => const LoadingView(message: 'Finding places near you...'),
        error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(havensProvider)),
        data: (all) {
          final list = _filter == 'all' ? all : all.where((h) => h.type == _filter).toList();
          return ListView(padding: pagePadding, children: [
            const DemoBanner(),
            Wrap(spacing: 8, children: [
              for (final f in const [('all', 'All'), ('hospital', 'Hospitals'), ('police', 'Police'), ('public', 'Public')])
                ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty) const EmptyView(icon: Icons.location_off_outlined, title: 'Nothing found', message: 'No places of this type were returned near you.'),
            for (final SafeHaven h in list)
              RsCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_icon(h.type)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  ]),
                  const SizedBox(height: 6),
                  Text('${_dist(h.distanceM)} away'),
                  Text(h.openNow == null ? 'Opening hours unavailable' : (h.openNow! ? 'Open now' : 'Closed now') + (h.hours != null ? ' (${h.hours})' : '')),
                  if (h.isDemo) const Text('Demo place, not a real listing', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${h.location.lat},${h.location.lng}'), mode: LaunchMode.externalApplication);
                      if (!ok && context.mounted) snack(context, 'Could not open directions.');
                    },
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Directions'),
                  ),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}
