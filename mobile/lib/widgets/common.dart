import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../providers/providers.dart';

/// Translucent blurred card. Use ONLY for overlays and floating controls.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(RS.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(color: cs.surface.withAlpha(215), borderRadius: BorderRadius.circular(RS.radius), border: Border.all(color: cs.outline.withAlpha(150))),
          child: child,
        ),
      ),
    );
  }
}

/// Solid, fully readable content card.
class RsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  const RsCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: color ?? cs.surface, borderRadius: BorderRadius.circular(RS.radius), border: Border.all(color: cs.outline), boxShadow: RS.shadow),
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(RS.radius), onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class _Meta {
  final Color bg, fg;
  final IconData icon;
  final String label;
  const _Meta(this.bg, this.fg, this.icon, this.label);
}

/// Risk is always communicated with an icon AND text, never colour alone.
class RiskBadge extends StatelessWidget {
  final String level;
  const RiskBadge(this.level, {super.key});
  _Meta get _m => switch (level) {
        'low' => const _Meta(Color(0xFFDDF3F0), Color(0xFF065F56), Icons.check_circle_outline, 'Lower estimated risk'),
        'moderate' => const _Meta(RS.amber, RS.amberText, Icons.warning_amber_rounded, 'Moderate risk'),
        'high' => const _Meta(RS.red, RS.redText, Icons.report_problem_outlined, 'High risk'),
        _ => const _Meta(Color(0xFFEAEFF5), Color(0xFF3D4B5C), Icons.help_outline, 'Risk unknown'),
      };
  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: m.bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: m.fg.withAlpha(80))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(m.icon, size: 16, color: m.fg),
        const SizedBox(width: 6),
        Text(m.label, style: TextStyle(color: m.fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
      ]),
    );
  }
}

class ConfidenceBadge extends StatelessWidget {
  final String level;
  const ConfidenceBadge(this.level, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xFFE6EEF9), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.insights_outlined, size: 16, color: Color(0xFF1B4C94)),
          const SizedBox(width: 6),
          Text('Confidence: $level', style: const TextStyle(color: Color(0xFF1B4C94), fontWeight: FontWeight.w600, fontSize: 12.5)),
        ]),
      );
}

class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        if (message != null) ...[const SizedBox(height: 12), Text(message!)],
      ]));
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final Widget? action;
  const EmptyView({super.key, required this.icon, required this.title, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ));
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorView(this.error, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.error_outline, title: 'Something went wrong', message: '$error',
        action: onRetry == null ? null : FilledButton(onPressed: onRetry, child: const Text('Try again')),
      );
}

/// Shown whenever any data on screen may be sample data.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoActiveProvider)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: RS.amber, borderRadius: BorderRadius.circular(14), border: Border.all(color: RS.amberText.withAlpha(90))),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.science_outlined, color: RS.amberText, size: 20),
        SizedBox(width: 10),
        Expanded(child: Text('DEMO MODE: the server is not connected. Routes, reports and places are sample data, not live information.', style: TextStyle(color: RS.amberText, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10), child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)));
}

/// Standard pushed-screen scaffold.
class PageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? fab;
  const PageScaffold({super.key, required this.title, required this.child, this.actions, this.fab});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title), actions: actions), floatingActionButton: fab, body: SafeArea(child: child));
}

const pagePadding = EdgeInsets.fromLTRB(20, 8, 20, 32);

void snack(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
