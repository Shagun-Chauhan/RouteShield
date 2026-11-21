import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routeshield/providers/survival_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'providers/providers.dart';
import 'router.dart';
import 'services/notification_service.dart';
import 'services/survival_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await NotificationService.instance.init();
  await SurvivalNotifier.instance.init(requestPermission: true);
  runApp(ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: const RouteShieldApp()));
}

class RouteShieldApp extends ConsumerWidget {
  const RouteShieldApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(survivalControllerProvider); // starts battery monitoring at launch
    return MaterialApp.router(
      title: 'RouteShield',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}