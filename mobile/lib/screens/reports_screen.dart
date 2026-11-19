import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/location_service.dart';
import '../widgets/common.dart';

const _categories = {'lighting': 'Poor lighting', 'obstruction': 'Road obstruction', 'hazard': 'Hazard', 'other': 'Other'};

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportsProvider);
    final fmt = DateFormat('d MMM, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Community reports')),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: () async {
            await context.push('/report/new');
            ref.invalidate(reportsProvider);
          },
          icon: const Icon(Icons.add_comment_outlined), label: const Text('Report'),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(reportsProvider)),
          data: (list) => ListView(padding: pagePadding, children: [
            const DemoBanner(),
            const RsCard(child: Text('Reports are reviewed before they affect any safety estimate and expire automatically. Unverified reports count for less.', style: TextStyle(height: 1.4))),
            if (list.isEmpty) const EmptyView(icon: Icons.campaign_outlined, title: 'No reports yet', message: 'Report poor lighting, obstructions or hazards to help others.'),
            for (final SafetyReport r in list)
              RsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text(_categories[r.category] ?? r.category, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), _StatusChip(r.status)]),
                const SizedBox(height: 6),
                Text(r.description),
                const SizedBox(height: 6),
                Text('Reported ${fmt.format(r.createdAt)}. Expires ${fmt.format(r.expiresAt)}.${r.approximateLocation ? ' Approximate location.' : ''}', style: const TextStyle(fontSize: 12.5)),
              ])),
          ]),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) {
    final (IconData i, String t, Color bg, Color fg) = switch (status) {
      'verified' => (Icons.verified_outlined, 'Verified', const Color(0xFFDDF3F0), const Color(0xFF065F56)),
      'rejected' => (Icons.block, 'Rejected', RS.red, RS.redText),
      'expired' => (Icons.hourglass_disabled_outlined, 'Expired', const Color(0xFFEAEFF5), const Color(0xFF3D4B5C)),
      _ => (Icons.hourglass_top, 'Pending review', RS.amber, RS.amberText),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 14, color: fg), const SizedBox(width: 4), Text(t, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700))]));
  }
}

class NewReportScreen extends ConsumerStatefulWidget {
  const NewReportScreen({super.key});
  @override
  ConsumerState<NewReportScreen> createState() => _NewReportState();
}

class _NewReportState extends ConsumerState<NewReportScreen> {
  final _key = GlobalKey<FormState>();
  final _desc = TextEditingController();
  String _cat = 'lighting';
  bool _approx = true, _busy = false;

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      var at = await LocationService.current();
      if (at != null && _approx) {
        double snap(double v) => (v / 0.005).round() * 0.005; // ~500 m grid
        at = GeoPoint(snap(at.lat), snap(at.lng));
      }
      await ref.read(repositoryProvider).submitReport(_cat, _desc.text.trim(), _approx, at);
      if (!mounted) return;
      snack(context, at == null ? 'Submitted without a location (location unavailable). It will be reviewed.' : 'Submitted for review.');
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, '$e');
      }
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'New report',
        child: Form(
          key: _key,
          child: ListView(padding: pagePadding, children: [
            DropdownButtonFormField<String>(
              value: _cat, decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final e in _categories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _cat = v ?? _cat),
            ),
            const SizedBox(height: 14),
            TextFormField(controller: _desc, maxLines: 4, maxLength: 300, decoration: const InputDecoration(labelText: 'What did you see?', alignLabelWithHint: true), validator: (v) => (v == null || v.trim().length < 10) ? 'Please add at least 10 characters' : null),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _approx, onChanged: (v) => setState(() => _approx = v), title: const Text('Approximate location'), subtitle: const Text('Shares an area of about 500 m instead of your exact position.')),
            const SizedBox(height: 8),
            const Text('Reports are reviewed before use and expire after 14 days. Do not include personal details about others.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Submit report')),
          ]),
        ),
      );
}
