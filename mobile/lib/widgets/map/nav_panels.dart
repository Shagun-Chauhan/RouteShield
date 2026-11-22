import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart' show RoutePreview;
import '../../providers/navigation_providers.dart';
import '../common.dart';
import 'map_widgets.dart';

/// Next-manoeuvre banner shown at the top during navigation.
class NavBanner extends StatelessWidget {
  final NavState nav;
  const NavBanner({super.key, required this.nav});
  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.navigation;
    String title, subtitle = '';
    if (nav.paused) {
      icon = Icons.pause_circle_outline;
      title = 'Navigation paused';
      subtitle = 'Tracking and check-ins continue.';
    } else if (nav.arrived) {
      icon = Icons.flag;
      title = 'Destination reached';
      subtitle = 'Tracking continues until you complete the journey.';
    } else if (nav.next != null) {
      icon = maneuverIcon(nav.next!.step);
      title = fmtDistance(nav.next!.distanceM);
      subtitle = nav.next!.step.instruction;
    } else if (nav.routeHasSteps) {
      title = 'Continue on route';
      subtitle = nav.remainingM == null ? '' : '${fmtDistance(nav.remainingM!)} to destination';
    } else {
      title = nav.remainingM == null ? 'Following your route' : fmtDistance(nav.remainingM!);
      subtitle = nav.remainingM == null
          ? 'Waiting for a GPS fix.'
          : 'remaining. The routing service sent no turn-by-turn steps for this route.';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RS.navy,
        borderRadius: BorderRadius.circular(RS.radius),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
            if (subtitle.isNotEmpty) Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(225), fontSize: 14)),
          ]),
        ),
      ]),
    );
  }
}

/// Deviation warning, reroute progress and reroute proposal. Nothing changes until the user accepts.
class RerouteCard extends ConsumerWidget {
  const RerouteCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider.select((s) => (s.deviated, s.rerouting, s.proposal, s.rerouteMessage)));
    final (deviated, rerouting, proposal, message) = nav;
    if (!deviated && !rerouting && proposal == null && message == null) return const SizedBox.shrink();
    final ctl = ref.read(navigationProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    Widget body;
    if (rerouting) {
      body = const Row(children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 12),
        Expanded(child: Text('Finding a new route from your current location...', style: TextStyle(fontWeight: FontWeight.w600))),
      ]);
    } else if (proposal != null) {
      final r = proposal.candidate;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('New route available', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text('${r.label}: ${r.distanceKm.toStringAsFixed(1)} km, about ${r.durationMin} min from where you are now.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [RiskBadge(r.riskLevel), ConfidenceBadge(r.confidenceLevel)]),
        const SizedBox(height: 4),
        Text('This is a recalculated route, not a live traffic update. Your current route stays until you accept.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: ctl.acceptReroute, child: const Text('Use this route'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: ctl.discardReroute, child: const Text('Keep current'))),
        ]),
      ]);
    } else if (deviated) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('You are off your selected route', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Your recent GPS readings are away from the route. Detours are fine if intended.'),
        if (message != null) ...[const SizedBox(height: 6), Text(message, style: const TextStyle(fontWeight: FontWeight.w600))],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: ctl.requestReroute, child: const Text('Recalculate'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: ctl.dismissDeviation, child: const Text("I'm fine"))),
        ]),
      ]);
    } else {
      body = Row(children: [
        Expanded(child: Text(message!, style: const TextStyle(fontWeight: FontWeight.w600))),
        TextButton(onPressed: ctl.discardReroute, child: const Text('OK')),
      ]);
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: proposal != null ? cs.surface : RS.amber,
        borderRadius: BorderRadius.circular(RS.radius),
        border: Border.all(color: proposal != null ? cs.outline : RS.amberText.withAlpha(90)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: proposal != null ? cs.onSurface : RS.amberText), child: body),
    );
  }
}

/// The single arrival prompt. Shown once when arrival is detected; "Continue tracking" hides it.
class ArrivalCard extends StatelessWidget {
  final VoidCallback onComplete, onContinue;
  const ArrivalCard({super.key, required this.onComplete, required this.onContinue});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RS.navy,
        borderRadius: BorderRadius.circular(RS.radius),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Row(children: [
          Icon(Icons.flag, color: Colors.white),
          SizedBox(width: 10),
          Expanded(child: Text('You have reached your destination', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
        ]),
        const SizedBox(height: 6),
        Text('Please confirm you are safe. Tracking and check-in reminders stay on until you complete the journey.', style: TextStyle(color: Colors.white.withAlpha(225), fontSize: 13.5)),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: RS.teal, minimumSize: const Size(0, 48)),
          onPressed: onComplete,
          icon: const Icon(Icons.verified_user),
          label: const Text("I'm safe: complete journey"),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
          onPressed: onContinue,
          child: const Text('Continue tracking'),
        ),
      ]),
    );
  }
}

/// Check-in reminder (due / missed), shown above the map.
class JourneyAlerts extends StatelessWidget {
  final NavState nav;
  final VoidCallback onCheckIn;
  const JourneyAlerts({super.key, required this.nav, required this.onCheckIn});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (nav.checkInDue)
        _AlertRow(
          icon: Icons.notifications_active_outlined,
          text: nav.checkInMissed ? 'Check-in missed. Tap if you are okay.' : 'Check-in due. Please confirm you are okay.',
          action: "I'm okay",
          onTap: onCheckIn,
          color: nav.checkInMissed ? RS.red : RS.amber,
        ),
    ]);
  }
}

class _AlertRow extends StatelessWidget {
  final IconData icon;
  final String text, action;
  final VoidCallback onTap;
  final Color color;
  const _AlertRow({required this.icon, required this.text, required this.action, required this.onTap, required this.color});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(color: Color.alphaBlend(color, cs.surface), borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outline.withAlpha(150))),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: onTap, child: Text(action)),
      ]),
    );
  }
}

/// Scrollable bottom-sheet body. The collapsed height shows only the header; everything below is
/// reachable by dragging the sheet up or scrolling, so content can never overflow the screen.
class FacilityRow {
  final String name, kind;
  final double distanceM;
  final VoidCallback onTap;
  const FacilityRow(this.name, this.kind, this.distanceM, this.onTap);
}

class ActiveNavSheet extends StatelessWidget {
  final ScrollController controller;
  final NavState nav;
  final RouteOption route;
  final Journey journey;
  final bool expanded;
  final List<FacilityRow> facilities;
  final String contactsLine;
  final VoidCallback onToggle, onPauseResume, onEnd, onCancel, onOpenDetails, onHavens, onPlan;
  const ActiveNavSheet({
    super.key, required this.controller, required this.nav, required this.route, required this.journey, required this.expanded, required this.facilities, required this.contactsLine,
    required this.onToggle, required this.onPauseResume, required this.onEnd, required this.onCancel,
    required this.onOpenDetails, required this.onHavens, required this.onPlan,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gps = gpsDescription(nav);
    final remaining = nav.remainingM;
    final kmh = nav.fix == null ? null : (nav.fix!.speedMps * 3.6).round();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final timeLeft = nav.eta == null ? null : nav.eta!.difference(DateTime.now());

    final summary = remaining == null
        ? 'Waiting for GPS fix'
        : [
            fmtDistance(remaining),
            if (timeLeft != null && !timeLeft.isNegative) fmtDuration(timeLeft),
            if (nav.eta != null) 'ETA ${fmtClock(nav.eta!)}',
          ].join('  ·  ');

    final risk = nav.risk;
    final atRisk = route.segments.where((s) => s.riskLevel == 'high').length;
    final unknown = route.segments.where((s) => s.riskLevel == 'unknown').length;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(250),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: cs.outline.withAlpha(120)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(
                  button: true,
                  label: expanded ? 'Collapse journey details' : 'Expand journey details',
                  child: InkWell(
                    onTap: onToggle,
                    child: SizedBox(
                      height: 28,
                      child: Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)))),
                    ),
                  ),
                ),
                Row(children: [
                  Expanded(child: Text('To ${journey.destination}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                  const SizedBox(width: 8),
                  Icon(expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, color: cs.onSurfaceVariant),
                ]),
                const SizedBox(height: 2),
                Text(summary, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: nav.fraction, minHeight: 6, backgroundColor: cs.outline.withAlpha(90)),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  PillChip(gps.text, icon: gps.icon, color: gps.color),
                  if (kmh != null && kmh > 0) PillChip('$kmh km/h', icon: Icons.speed),
                  if (nav.paused) const PillChip('Paused', icon: Icons.pause, color: Color(0xFFB7791F)),
                ]),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Divider(color: cs.outline.withAlpha(120)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: onPauseResume,
                      icon: Icon(nav.paused ? Icons.play_arrow : Icons.pause),
                      label: Text(nav.paused ? 'Resume' : 'Pause'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: RS.teal),
                      onPressed: onEnd,
                      icon: const Icon(Icons.check),
                      label: const Text('Arrived'),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: onCancel, child: const Text('Cancel journey'))),
                const SectionTitle('Safety on this route'),
                Wrap(spacing: 8, runSpacing: 8, children: [RiskBadge(route.riskLevel), ConfidenceBadge(route.confidenceLevel)]),
                if (risk != null) ...[
                  const SizedBox(height: 10),
                  _Row(
                    risk.segment.riskLevel == 'high' ? Icons.report_problem_outlined : Icons.help_outline,
                    risk.segment.riskLevel == 'high'
                        ? '${risk.inside ? 'You are on' : 'In ${fmtDistance(risk.distanceM)}:'} ${risk.segment.name}. High estimated risk.'
                        : '${risk.inside ? 'You are on' : 'In ${fmtDistance(risk.distanceM)}:'} ${risk.segment.name}. Not enough information to assess it (this does not mean it is safe).',
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '$atRisk high-risk and $unknown unassessed section(s) on this route. Tap a coloured section on the map for its evidence.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                if (route.explanation.isNotEmpty) ...[const SizedBox(height: 6), Text(route.explanation, style: const TextStyle(fontSize: 13))],
                const SizedBox(height: 4),
                Text('Estimates from available data only. No route is guaranteed safe.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SectionTitle('Nearby emergency facilities'),
                if (facilities.isEmpty)
                  Text('None found nearby yet. Nearby places load from OpenStreetMap when you have a GPS fix.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))
                else
                  for (final f in facilities)
                    InkWell(
                      onTap: f.onTap,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(children: [
                          const Icon(Icons.local_hospital_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${f.name}  (${f.kind})', maxLines: 2, overflow: TextOverflow.ellipsis)),
                          Text(fmtDistance(f.distanceM), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                const SectionTitle('Trusted contacts'),
                _Row(Icons.contacts_outlined, contactsLine),
                const SectionTitle('Journey'),
                _Row(Icons.route, 'Travelled ${fmtDistance(nav.travelledM)}${remaining == null ? '' : ', ${fmtDistance(remaining)} to go'}'),
                if (nav.eta != null) _Row(Icons.schedule, 'ETA ${fmtClock(nav.eta!)} based on ${nav.etaBasis}. Not live traffic.'),
                _Row(Icons.timer_outlined, nav.nextCheckIn == null ? 'No check-in scheduled' : 'Next check-in at ${fmtClock(nav.nextCheckIn!)}'),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: onHavens, icon: const Icon(Icons.local_hospital_outlined), label: const Text('Safe places')),
                  OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: onPlan, icon: const Icon(Icons.checklist_rtl), label: const Text('Safety plan')),
                  OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: onOpenDetails, icon: const Icon(Icons.tune), label: const Text('Journey controls')),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Row(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ]),
      );
}

/// Route preview (planned journey): alternatives, selected route facts and the Start button.
class RoutePreviewSheet extends StatelessWidget {
  final ScrollController controller;
  final RoutePreview preview;
  final RouteOption route;
  final bool sample;
  final void Function(RouteOption) onSelect;
  final VoidCallback onStart, onClose;
  const RoutePreviewSheet({super.key, required this.controller, required this.preview, required this.route, required this.sample, required this.onSelect, required this.onStart, required this.onClose});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final high = route.segments.where((s) => s.riskLevel == 'high').length;
    final unknown = route.segments.where((s) => s.riskLevel == 'unknown').length;
    final eta = DateTime.now().add(Duration(minutes: route.durationMin));
    return _SheetShell(controller: controller, children: [
      Row(children: [
        Expanded(child: Text('To ${preview.destination}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
        IconButton(onPressed: onClose, tooltip: 'Close preview', icon: const Icon(Icons.close)),
      ]),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final r in preview.routes)
          ChoiceChip(label: Text('${r.label} · ${r.durationMin} min'), selected: r.id == route.id, onSelected: (_) => onSelect(r)),
      ]),
      const SizedBox(height: 10),
      Text('${route.distanceKm.toStringAsFixed(1)} km  ·  ${route.durationMin} min  ·  ETA ${fmtClock(eta)}${route.extraMin > 0 ? '  (+${route.extraMin} min vs fastest)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        RiskBadge(route.riskLevel),
        ConfidenceBadge(route.confidenceLevel),
        PillChip(sample ? 'Sample data' : 'RouteShield server', icon: sample ? Icons.science_outlined : Icons.cloud_done_outlined, color: sample ? const Color(0xFFB7791F) : null),
      ]),
      if (high > 0 || unknown > 0) ...[
        const SizedBox(height: 8),
        Text('${high > 0 ? '$high high-risk section(s). ' : ''}${unknown > 0 ? '$unknown section(s) without enough information (not the same as safe).' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
      if (route.explanation.isNotEmpty) ...[const SizedBox(height: 6), Text(route.explanation, style: const TextStyle(fontSize: 13))],
      const SizedBox(height: 6),
      Text('Alternatives are drawn on the map; tap one to select it, or tap a coloured section for its evidence. ETA is from the routing provider (no live traffic). Estimates only, not a guarantee of safety.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),
      FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 52)), onPressed: onStart, icon: const Icon(Icons.navigation), label: const Text('Start journey')),
    ]);
  }
}

/// Route facts shown (when a route is selected but no journey is active).
class RoutePanel extends StatelessWidget {
  final RouteOption route;
  final bool segmentsTappable;
  final ScrollController controller;
  const RoutePanel(this.route, {super.key, required this.segmentsTappable, required this.controller});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SheetShell(
      controller: controller,
      children: [
        Text('${route.label} route', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 4),
        Text('${route.distanceKm.toStringAsFixed(1)} km  ·  ${route.durationMin} min${route.extraMin > 0 ? '  (+${route.extraMin} min vs fastest)' : ''}'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [RiskBadge(route.riskLevel), ConfidenceBadge(route.confidenceLevel)]),
        if (route.explanation.isNotEmpty) ...[const SizedBox(height: 8), Text(route.explanation, style: const TextStyle(fontSize: 13))],
        const SizedBox(height: 6),
        Text(
          segmentsTappable
              ? 'Tap a coloured section of the route for its safety details. Grey means not enough information. Estimates only, not a guarantee of safety.'
              : 'Section-by-section detail is not available for this route yet. Estimates only, not a guarantee of safety.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class SegmentPanel extends StatelessWidget {
  final SegmentAssessment s;
  final VoidCallback onClose;
  final ScrollController controller;
  const SegmentPanel(this.s, {super.key, required this.onClose, required this.controller});
  @override
  Widget build(BuildContext context) {
    final fresh = s.freshestEvidenceAt;
    return _SheetShell(controller: controller, children: [
      Row(children: [
        Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close), tooltip: 'Close'),
      ]),
      Wrap(spacing: 8, runSpacing: 8, children: [RiskBadge(s.riskLevel), ConfidenceBadge(s.confidenceLevel)]),
      const SizedBox(height: 8),
      Text(s.riskScore == null ? 'Risk score: not available' : 'Risk score: ${s.riskScore}'),
      Text(fresh == null ? 'Evidence date: not available' : 'Newest evidence: ${fresh.day}/${fresh.month}/${fresh.year}'),
      if (s.reasons.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Why', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final r in s.reasons) Text('•  $r'),
      ],
      const SizedBox(height: 8),
      Text('Source: RouteShield server assessment. The server does not report a source for each factor, so evidence is shown only as listed above.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      if (s.missingInformation.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Not available', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final m in s.missingInformation) Text('•  $m'),
      ],
    ]);
  }
}

class _SheetShell extends StatelessWidget {
  final ScrollController controller;
  final List<Widget> children;
  const _SheetShell({required this.controller, required this.children});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(250),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: cs.outline.withAlpha(120)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)))),
          ...children,
        ],
      ),
    );
  }
}
