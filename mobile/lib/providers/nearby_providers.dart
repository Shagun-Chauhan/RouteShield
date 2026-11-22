import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/nav_config.dart';
import '../models/models.dart';
import '../services/deviation_detector.dart';
import '../services/nearby_places_service.dart';
import 'survival_providers.dart' show survivalProfileProvider;

final nearbyServiceProvider = Provider<NearbyPlacesService>((ref) => NearbyPlacesService());

class NearbyState {
  final List<NearbyPlace> places;
  final bool loading;
  final String? error;
  final DateTime? fetchedAt;
  final bool fromCache;
  final GeoPoint? center;
  const NearbyState({this.places = const [], this.loading = false, this.error, this.fetchedAt, this.fromCache = false, this.center});
}

/// Throttled, debounced, cancel-safe loader for OSM places around the user.
///  * auto refresh only after moving [NavConfig.nearbyMinMoveM] (or when the cache expired);
///  * at most one network request per [NavConfig.nearbyMinInterval];
///  * a 1.5 s debounce collapses bursts of GPS updates;
///  * survival mode stops automatic polling (manual refresh still works);
///  * a response that arrives after a newer request started is discarded;
///  * on failure the previous places stay on screen together with the error.
class NearbyPlacesController extends Notifier<NearbyState> {
  Timer? _debounce;
  int _seq = 0;
  DateTime? _lastRequest;

  @override
  NearbyState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const NearbyState();
  }

  void onLocation(GeoPoint p) {
    if (ref.read(survivalProfileProvider).survival) return;
    final c = state.center;
    final fresh = state.fetchedAt != null && DateTime.now().difference(state.fetchedAt!) < NavConfig.nearbyCacheTtl;
    if (c != null && fresh && distanceMeters(c, p) < NavConfig.nearbyMinMoveM) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () => _load(p, force: false));
  }

  /// User-initiated refresh (bypasses the cache and the survival-mode pause, not the min interval).
  Future<void> refresh(GeoPoint p) => _load(p, force: true);

  Future<void> _load(GeoPoint p, {required bool force}) async {
    if (state.loading) return;
    final last = _lastRequest;
    if (last != null && DateTime.now().difference(last) < NavConfig.nearbyMinInterval) {
      if (force) state = NearbyState(places: state.places, fetchedAt: state.fetchedAt, center: state.center, error: 'Please wait a moment before refreshing again.');
      return;
    }
    final my = ++_seq;
    _lastRequest = DateTime.now();
    state = NearbyState(places: state.places, fetchedAt: state.fetchedAt, center: state.center, loading: true);
    try {
      final r = await ref.read(nearbyServiceProvider).fetch(p, bypassCache: force);
      if (my != _seq) return;
      state = NearbyState(places: r.places, fetchedAt: r.fetchedAt, fromCache: r.fromCache, center: p);
    } catch (e) {
      if (my != _seq) return;
      state = NearbyState(places: state.places, fetchedAt: state.fetchedAt, center: state.center, error: '$e');
    }
  }
}

final nearbyPlacesProvider = NotifierProvider<NearbyPlacesController, NearbyState>(NearbyPlacesController.new);
