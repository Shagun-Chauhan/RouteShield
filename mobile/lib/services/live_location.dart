import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/providers.dart';
import '../providers/survival_providers.dart';

enum LocationAccess { granted, denied, deniedForever, serviceOff }

Future<LocationAccess> checkLocationAccess({bool request = false}) async {
  if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied && request) p = await Geolocator.requestPermission();
  if (p == LocationPermission.deniedForever) return LocationAccess.deniedForever;
  if (p == LocationPermission.denied) return LocationAccess.denied;
  return LocationAccess.granted;
}

/// Invalidate to re-run the permission flow (e.g. after returning from settings).
final locationAccessProvider = FutureProvider.autoDispose<LocationAccess>((ref) => checkLocationAccess(request: true));

/// THE single GPS subscription for the app's map and journey screens.
/// Runs only while the Map tab is visible or a journey is active (so the always-mounted
/// IndexedStack map tab does not drain battery). Survival mode lowers accuracy and update rate,
/// using the intervals from SurvivalConfig; it never stops tracking during a journey.
final livePositionProvider = StreamProvider.autoDispose<Position>((ref) async* {
  final journeyActive = ref.watch(activeJourneyProvider.select((j) => j != null));
  final mapVisible = ref.watch(shellIndexProvider.select((i) => i == 1));
  if (!journeyActive && !mapVisible) return;

  final access = await ref.watch(locationAccessProvider.future);
  if (access != LocationAccess.granted) return;

  final saver = ref.watch(survivalProfileProvider.select((p) => p.survival));
  final interval = ref.read(survivalProfileProvider).locationInterval;
  final accuracy = saver ? LocationAccuracy.medium : LocationAccuracy.high;
  final filter = saver ? 50 : (journeyActive ? 10 : 25);

  final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: accuracy,
          distanceFilter: filter,
          intervalDuration: interval,
          // Foreground service keeps GPS running while the app is backgrounded during a journey.
          // Needs FOREGROUND_SERVICE + FOREGROUND_SERVICE_LOCATION permissions in AndroidManifest.
          foregroundNotificationConfig: journeyActive
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'RouteShield journey active',
                  notificationText: 'Tracking your location for your safety.',
                  enableWakeLock: true,
                  setOngoing: true,
                )
              : null,
        )
      : LocationSettings(accuracy: accuracy, distanceFilter: filter);
  yield* Geolocator.getPositionStream(locationSettings: settings);
});
