import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class RoutesScreen extends ConsumerWidget {
  final String destination;
  const RoutesScreen({super.key, required this.destination});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(routesProvider(destination));
    return PageScaffold(
      title: 'Route comparison',
      child: async.when(
        loading: () => const LoadingView(message: 'Comparing routes...'),
        error: (e, _) => ErrorView(e,
            onRetry: () => ref.invalidate(routesProvider(destination))),
        data: (routes) => routes.isEmpty
            ? EmptyView(
                icon: Icons.alt_route,
                title: 'No routes found',
                message:
                    'We could not find a route to "$destination". Check the destination and try again.',
                action: FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('Change destination')))
            : ListView(padding: pagePadding, children: [
                const DemoBanner(),
                Text('To $destination',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'Risk and confidence are shown separately. A missing report never means a road is safe.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13)),
                const SizedBox(height: 14),
                for (final r in routes)
                  _RouteCard(route: r, destination: destination),
              ]),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RouteOption route;
  final String destination;
  const _RouteCard({required this.route, required this.destination});

  void _start(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StartSheet(route: route, destination: destination));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final attention = route.segments.where((s) => s.riskLevel != 'low').length;
    return RsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(route.label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800))),
          if (route.recommended)
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: cs.secondary,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('Recommended',
                    style: TextStyle(
                        color: cs.onSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12))),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _metric(Icons.schedule, '${route.durationMin} min'),
          _metric(
              Icons.straighten, '${route.distanceKm.toStringAsFixed(1)} km'),
          _metric(Icons.add_circle_outline,
              route.extraMin == 0 ? 'Fastest' : '+${route.extraMin} min'),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          RiskBadge(route.riskLevel),
          ConfidenceBadge(route.confidenceLevel)
        ]),
        const SizedBox(height: 12),
        Text(route.explanation, style: const TextStyle(height: 1.4)),
        if (attention > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 6),
            Text('$attention segment(s) need attention or have unknown risk',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))
          ]),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => context.push('/segments', extra: route),
                  child: const Text('Segments'))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(
                  onPressed: () => _start(context),
                  child: const Text('Start'))),
        ]),
      ]),
    );
  }

  Widget _metric(IconData i, String t) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 18),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w600))
      ]);
}

class _StartSheet extends ConsumerStatefulWidget {
  final RouteOption route;
  final String destination;
  const _StartSheet({required this.route, required this.destination});
  @override
  ConsumerState<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends ConsumerState<_StartSheet> {
  final _sel = <String>{};
  bool _busy = false;
  int? _mins;

  Future<void> _start() async {
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    final nav = Navigator.of(context);
    try {
      final j = await ref.read(repositoryProvider).startJourney(
          widget.destination,
          widget.route,
          _mins ?? ref.read(checkInMinutesProvider),
          _sel.toList());
      ref.read(activeJourneyProvider.notifier).state = j;
      ref.read(selectedRouteProvider.notifier).state = widget.route;
      nav.pop();
      router.push('/journey');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final mins = _mins ?? ref.watch(checkInMinutesProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Start journey',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  '${widget.route.label} to ${widget.destination}, about ${widget.route.durationMin} min'),
              const SectionTitle('Check-in reminder every'),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 10, label: Text('10 min')),
                  ButtonSegment(value: 15, label: Text('15 min')),
                  ButtonSegment(value: 30, label: Text('30 min'))
                ],
                selected: {mins ?? 15},
                onSelectionChanged: (s) => setState(() => _mins = s.first),
              ),
              const SectionTitle('Trusted contacts for this journey'),
              contacts.when(
                loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator()),
                error: (e, _) => Text('Could not load contacts: $e'),
                data: (list) => list.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            const Text(
                                'You have no trusted contacts yet. You can still start, but no one can be alerted.'),
                            TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  context.push('/contacts');
                                },
                                child: const Text('Add a contact')),
                          ])
                    : Column(children: [
                        for (final c in list)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _sel.contains(c.id),
                            title: Text(c.name),
                            subtitle: Text(c.consentToShare
                                ? c.phone
                                : '${c.phone} (no sharing consent)'),
                            onChanged: (v) => setState(() =>
                                v == true ? _sel.add(c.id) : _sel.remove(c.id)),
                          ),
                      ]),
              ),
              const SizedBox(height: 8),
              Text(
                  'Contacts are alerted only if you agree at the time. Arrival expected around ${DateFormat('HH:mm').format(DateTime.now().add(Duration(minutes: widget.route.durationMin)))}.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13)),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _busy ? null : _start,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Start journey')),
            ]),
      ),
    );
  }
}

class SegmentsScreen extends StatelessWidget {
  final RouteOption route;
  const SegmentsScreen({super.key, required this.route});
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM, HH:mm');
    return PageScaffold(
      title: 'Segment safety',
      child: ListView(padding: pagePadding, children: [
        const DemoBanner(),
        Text('${route.label} route',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            'Estimated risk and evidence confidence are separate. "Risk unknown" means there is not enough evidence. It does not mean safe.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13)),
        const SizedBox(height: 14),
        if (route.segments.isEmpty)
          const EmptyView(
              icon: Icons.route,
              title: 'No segment data',
              message: 'Segment details are not available for this route.'),
        for (final s in route.segments)
          RsCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                RiskBadge(s.riskLevel),
                ConfidenceBadge(s.confidenceLevel)
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.update, size: 18),
                const SizedBox(width: 6),
                Text(s.freshestEvidenceAt == null
                    ? 'No evidence recorded'
                    : 'Latest evidence: ${fmt.format(s.freshestEvidenceAt!)}')
              ]),
              if (s.riskScore != null)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Risk score: ${s.riskScore}/100')),
              if (s.reasons.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Reasons for caution',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                for (final r in s.reasons)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(r))
                          ])),
              ],
              if (s.missingInformation.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEAEFF5),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.info_outline, size: 18, color: RS.text),
                          SizedBox(width: 6),
                          Text('Missing information',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, color: RS.text))
                        ]),
                        const SizedBox(height: 4),
                        Text(s.missingInformation.join(', '),
                            style: const TextStyle(color: RS.text)),
                      ]),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}
