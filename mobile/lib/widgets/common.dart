import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config.dart';
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

/// Shown whenever any data on screen may be sample data. Explains the real cause and lets the
/// user re-test the connection; it only disappears once the backend actually answers.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    ref.invalidate(backendProbeProvider);
    final r = await ref.read(backendProbeProvider.future);
    if (!context.mounted) return;
    if (ref.read(apiClientProvider).token == 'demo') {
      snack(context, 'Server reachable: ${r.reachable}. You are on a demo session, so sign in again with a real account.');
      return;
    }
    if (r.reachable) {
      ref.read(demoActiveProvider.notifier).state = false;
      ref.invalidate(havensProvider);
      ref.invalidate(contactsProvider);
      ref.invalidate(reportsProvider);
      ref.invalidate(historyProvider);
      ref.invalidate(notificationsProvider);
      snack(context, 'Connected to the RouteShield server.');
    } else {
      snack(context, r.detail);
    }
  }

  Future<void> _details(BuildContext context, WidgetRef ref) async {
    final demoSession = ref.read(apiClientProvider).token == 'demo';
    final probe = await ref.read(backendProbeProvider.future);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Why is demo mode on?'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('API address in this build:\n${AppConfig.apiBaseUrl}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Connection test: ${probe.detail}'),
            if (demoSession) ...[const SizedBox(height: 8), const Text('You are signed in with a demo session (created when the server could not be reached at login). Sign in again once the server is reachable.')],
            const SizedBox(height: 8),
            const Text('Common causes:\n'
                '• 10.0.2.2 only works from the Android emulator. On a real phone build with --dart-define=API_BASE_URL=http://<PC LAN IP>:4000/api (same Wi-Fi).\n'
                '• Backend not running or a firewall blocks the port.\n'
                '• Plain http:// is blocked on Android 9+ unless usesCleartextTraffic is enabled (debug) or you use https.\n'
                '• Missing INTERNET permission in AndroidManifest.xml.'),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoActiveProvider)) return const SizedBox.shrink();
    final demoSession = ref.watch(authProvider.select((a) => a.token == 'demo'));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(color: RS.amber, borderRadius: BorderRadius.circular(14), border: Border.all(color: RS.amberText.withAlpha(90))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.science_outlined, color: RS.amberText, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text('SAMPLE DATA: the RouteShield server is not connected, so routes, reports and places shown from it are samples, not live information. GPS and OpenStreetMap data are still real.', style: TextStyle(color: RS.amberText, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => _details(context, ref), child: const Text('Why?')),
          TextButton(onPressed: () => _retry(context, ref), child: const Text('Retry')),
          if (demoSession)
            TextButton(
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) GoRouter.of(context).go('/login');
              },
              child: const Text('Sign in'),
            ),
        ]),
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
