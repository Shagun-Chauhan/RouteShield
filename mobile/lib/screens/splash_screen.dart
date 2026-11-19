import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../providers/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashState();
}

class _SplashState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      final onboarded = ref.read(sharedPrefsProvider).getBool('onboarded') == true;
      final loggedIn = ref.read(authProvider).loggedIn;
      context.go(!onboarded ? '/onboarding' : (loggedIn ? '/home' : '/login'));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: RS.gradient),
          child: Center(
            child: FadeTransition(
              opacity: _c,
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.shield_outlined, size: 84, color: Colors.white),
                  SizedBox(height: 16),
                  Text('RouteShield', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('Travel with more information', style: TextStyle(color: Colors.white70, fontSize: 15)),
                ]),
              ),
            ),
          ),
        ),
      );
}
