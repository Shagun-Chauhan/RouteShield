import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/navigation_providers.dart';
import '../providers/providers.dart';

class ShellScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const ShellScaffold({super.key, required this.shell});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instantiate the navigation controller once so GPS filtering, deviation checks and check-in
    // reminders run for the whole session, whichever tab or screen is open.
    ref.read(navigationProvider);
    // Keep the visible-tab index in sync so the map can pause GPS while hidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(shellIndexProvider) != shell.currentIndex) ref.read(shellIndexProvider.notifier).state = shell.currentIndex;
    });
    // During active navigation on the map tab, hide the bar to give the map the full screen.
    final navigating = ref.watch(activeJourneyProvider.select((j) => j != null)) && shell.currentIndex == 1;
    return Scaffold(
      body: shell,
      bottomNavigationBar: navigating ? null : ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
              NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Guardian'),
              NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Reports'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}
