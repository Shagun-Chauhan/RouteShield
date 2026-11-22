import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/config.dart';
import '../data/repository.dart';
import '../models/destination.dart';
import '../models/models.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Override in main()'));
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final repositoryProvider = Provider<Repository>((ref) => Repository(ref));
final demoActiveProvider = StateProvider<bool>((ref) => false);

/// Result of asking the backend whether it is reachable. Used to explain WHY demo mode is on.
class BackendProbe {
  final bool reachable;
  final String detail;
  const BackendProbe(this.reachable, this.detail);
}

/// Any HTTP answer (even 404) proves the server is up; only connection failures count as unreachable.
final backendProbeProvider = FutureProvider.autoDispose<BackendProbe>((ref) async {
  final uri = Uri.parse('${AppConfig.apiBaseUrl}/health');
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 5));
    return BackendProbe(r.statusCode < 500, 'The server answered ${r.statusCode} at $uri');
  } on SocketException catch (e) {
    return BackendProbe(false, 'Cannot connect to $uri (${e.message}).');
  } on TimeoutException {
    return BackendProbe(false, 'No answer from $uri within 5 seconds.');
  } catch (e) {
    return BackendProbe(false, 'Could not reach $uri: $e');
  }
});

// ---------- Auth ----------
class AuthState {
  final String? token, name, email;
  const AuthState({this.token, this.name, this.email});
  bool get loggedIn => token != null;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final p = ref.read(sharedPrefsProvider);
    final t = p.getString('token');
    ref.read(apiClientProvider).token = t;
    if (t == 'demo') Future.microtask(() => ref.read(demoActiveProvider.notifier).state = true);
    return AuthState(token: t, name: p.getString('name'), email: p.getString('email'));
  }

  Future<void> _store(AuthResult r, String email) async {
    final p = ref.read(sharedPrefsProvider);
    await p.setString('token', r.token);
    await p.setString('name', r.name);
    await p.setString('email', email);
    ref.read(apiClientProvider).token = r.token;
    state = AuthState(token: r.token, name: r.name, email: email);
  }

  Future<void> login(String email, String pw) async => _store(await ref.read(repositoryProvider).login(email, pw), email);
  Future<void> register(String name, String email, String pw) async => _store(await ref.read(repositoryProvider).register(name, email, pw), email);

  Future<void> logout() async {
    final p = ref.read(sharedPrefsProvider);
    await p.remove('token');
    ref.read(apiClientProvider).token = null;
    ref.read(demoActiveProvider.notifier).state = false;
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// ---------- Settings ----------
final themeModeProvider = StateProvider<ThemeMode>((ref) => ref.read(sharedPrefsProvider).getBool('dark') == true ? ThemeMode.dark : ThemeMode.light);
final callerNameProvider = StateProvider<String>((ref) => ref.read(sharedPrefsProvider).getString('caller') ?? 'Mom');
final checkInMinutesProvider = StateProvider<int>((ref) => ref.read(sharedPrefsProvider).getInt('checkin') ?? 15);

// ---------- Data ----------
final routesProvider = FutureProvider.autoDispose.family<List<RouteOption>, Destination>((ref, dest) async {
  final origin = await LocationService.current();
  return ref.read(repositoryProvider).fetchRoutes(origin ?? AppConfig.defaultCenter, dest);
});
final geocoderProvider = Provider<GeocodingService>((ref) => GeocodingService());
/// Index of the visible bottom-nav tab (kept in sync by ShellScaffold). Lets the map pause GPS when hidden.
final shellIndexProvider = StateProvider<int>((ref) => 0);
final contactsProvider = FutureProvider.autoDispose<List<TrustedContact>>((ref) => ref.read(repositoryProvider).contacts());
final reportsProvider = FutureProvider.autoDispose<List<SafetyReport>>((ref) => ref.read(repositoryProvider).reports());
final historyProvider = FutureProvider.autoDispose<List<Journey>>((ref) => ref.read(repositoryProvider).history());
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) => ref.read(repositoryProvider).notifications());
final havensProvider = FutureProvider.autoDispose<List<SafeHaven>>((ref) async {
  final at = await LocationService.current();
  return ref.read(repositoryProvider).safeHavens(at ?? AppConfig.defaultCenter);
});

// ---------- Journey state ----------
final selectedRouteProvider = StateProvider<RouteOption?>((ref) => null);
final activeJourneyProvider = StateProvider<Journey?>((ref) => null);

/// Route alternatives currently being compared on the map (planned journey, before Start).
class RoutePreview {
  final String destination;
  final List<RouteOption> routes;
  final String selectedId;
  const RoutePreview(this.destination, this.routes, this.selectedId);
}

final routePreviewProvider = StateProvider<RoutePreview?>((ref) => null);

// ---------- Battery (real device value, refreshed every 20 s) ----------
Stream<int> _batteryStream() async* {
  final b = Battery();
  while (true) {
    try {
      yield await b.batteryLevel;
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 20));
  }
}

final batteryProvider = StreamProvider<int>((ref) => _batteryStream());

// ---------- Low-Battery Survival Mode (manual switch; also auto-applies at <=15% battery) ----------
final survivalModeProvider = StateProvider<bool>((ref) => ref.read(sharedPrefsProvider).getBool('survival') == true);
