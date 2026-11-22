import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../services/emergency_alert.dart';
import '../../services/emergency_service.dart';
import '../common.dart';
import 'map_widgets.dart';

/// Opens the SOS sheet. Nothing is sent until the user taps an action.
Future<void> showSosSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => const _SosSheet(),
    );

class _SosSheet extends ConsumerStatefulWidget {
  const _SosSheet();
  @override
  ConsumerState<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends ConsumerState<_SosSheet> {
  late final Future<SosPlan> _plan = ref.read(emergencyServiceProvider).prepare();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final svc = ref.read(emergencyServiceProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: FutureBuilder<SosPlan>(
          future: _plan,
          builder: (context, snap) {
            final plan = snap.data;
            final fix = plan?.fix;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Emergency help', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: sosRed, minimumSize: const Size(0, 56)),
                onPressed: () async {
                  final ok = await svc.callEmergency();
                  if (!ok && context.mounted) snack(context, 'Could not open the phone dialler.');
                },
                icon: const Icon(Icons.call),
                label: const Text('Call ${EmergencyService.emergencyNumber}'),
              ),
              const SizedBox(height: 16),
              if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
              else ...[
                Text(
                  fix == null
                      ? 'No location has been recorded yet, so a message would not include where you are.'
                      : '${plan!.fixIsLive ? 'Current' : 'Last known'} location, recorded ${DateFormat('HH:mm:ss').format(fix.at)} (${ageText(DateTime.now().difference(fix.at))})'
                          '${fix.accuracy == null ? '' : ', ±${fix.accuracy!.round()} m'}.'
                          '${plan.fixIsLive ? '' : ' It may not be where you are now.'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                if (plan!.contacts.isEmpty)
                  Text('No trusted contact who agreed to receive your location was found. Add one in Trusted contacts.', style: TextStyle(color: cs.onSurfaceVariant))
                else ...[
                  Text('Will message: ${plan.contacts.map((c) => c.name).join(', ')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: cs.outline.withAlpha(40), borderRadius: BorderRadius.circular(12)),
                    child: Text(plan.message, style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                    onPressed: () async {
                      final ok = await svc.openSms(plan);
                      if (!context.mounted) return;
                      snack(context, ok ? 'Message opened. Press send in your messaging app.' : 'Could not open the messaging app.');
                    },
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Message my trusted contacts'),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'RouteShield opens the message for you to send and cannot confirm that it was sent or received. '
                  'If you are in danger, call the emergency number first.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ]);
          },
        ),
      ),
    );
  }
}
