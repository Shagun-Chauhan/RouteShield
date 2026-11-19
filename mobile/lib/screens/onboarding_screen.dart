import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  final _pc = PageController();
  int _i = 0;
  static const _pages = [
    (Icons.alt_route, 'Compare routes by safety', 'See estimated risk, evidence confidence and travel time side by side, segment by segment.'),
    (Icons.shield_outlined, 'Journey Guardian', 'Share a journey with trusted contacts, set check-ins and decide when they are alerted.'),
    (Icons.battery_alert_outlined, 'Prepared for the unexpected', 'Low-battery mode, safe havens nearby and a plan for lost signal or GPS.\n\nRouteShield supports your decisions. It cannot guarantee safety or replace emergency services (112 in India).'),
  ];

  Future<void> _finish() async {
    await ref.read(sharedPrefsProvider).setBool('onboarded', true);
    if (mounted) context.go('/login');
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = _i == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _finish, child: const Text('Skip'))),
          Expanded(
            child: PageView(
              controller: _pc,
              onPageChanged: (v) => setState(() => _i = v),
              children: [
                for (final p in _pages)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(color: cs.secondary.withAlpha(30), shape: BoxShape.circle),
                        child: Icon(p.$1, size: 72, color: cs.secondary),
                      ),
                      const SizedBox(height: 32),
                      Text(p.$2, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      Text(p.$3, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16, height: 1.45)),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < _pages.length; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.all(4),
                width: k == _i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(color: k == _i ? cs.secondary : cs.outline, borderRadius: BorderRadius.circular(8)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              onPressed: last ? _finish : () => _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
              child: Text(last ? 'Get started' : 'Next'),
            ),
          ),
        ]),
      ),
    );
  }
}
