import 'package:go_router/go_router.dart';
import 'models/destination.dart';
import 'models/models.dart';
import 'screens/auth_screens.dart';
import 'screens/battery_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/fake_call_screen.dart';
import 'screens/guardian_screen.dart';
import 'screens/havens_screen.dart';
import 'screens/history_screens.dart';
import 'screens/home_screen.dart';
import 'screens/journey_screen.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/routes_screens.dart';
import 'screens/search_screen.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (c, s) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
    StatefulShellRoute.indexedStack(
      builder: (c, s, shell) => ShellScaffold(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (c, s) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (c, s) => const MapScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/guardian', builder: (c, s) => const GuardianScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/reports', builder: (c, s) => const ReportsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())]),
      ],
    ),
    GoRoute(path: '/search', builder: (c, s) => const SearchScreen()),
    GoRoute(path: '/routes', builder: (c, s) {
      final e = s.extra;
      return RoutesScreen(destination: e is Destination ? e : Destination(e is String ? e : ''));
    }),
    GoRoute(path: '/segments', builder: (c, s) => SegmentsScreen(route: s.extra as RouteOption)),
    GoRoute(path: '/journey', builder: (c, s) => const ActiveJourneyScreen()),
    GoRoute(path: '/contacts', builder: (c, s) => const ContactsScreen()),
    GoRoute(path: '/battery', builder: (c, s) => const BatteryScreen()),
    GoRoute(path: '/havens', builder: (c, s) => const HavensScreen()),
    GoRoute(path: '/plan', builder: (c, s) => const PlanScreen()),
    GoRoute(path: '/history', builder: (c, s) => const HistoryScreen()),
    GoRoute(path: '/notifications', builder: (c, s) => const NotificationsScreen()),
    GoRoute(path: '/call', builder: (c, s) => const FakeCallScreen()),
    GoRoute(path: '/report/new', builder: (c, s) => const NewReportScreen()),
  ],
);
