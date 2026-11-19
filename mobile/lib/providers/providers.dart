import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/config.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../services/location_service.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Override in main()'));
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final repositoryProvider = Provider<Repository>((ref) => Repository(ref));
final demoActiveProvider = StateProvider<bool>((ref) => false);

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
final routesProvider = FutureProvider.autoDispose.family<List<RouteOption>, String>((ref, dest) async {
  final origin = await LocationService.current();
  return ref.read(repositoryProvider).fetchRoutes(origin ?? AppConfig.defaultCenter, dest);
});
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
