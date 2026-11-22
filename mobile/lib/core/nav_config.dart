/// Tunable navigation thresholds in one place.
class NavConfig {
  // ---- GPS filtering ----
  /// Fixes with a reported accuracy worse than this (metres) are ignored for navigation.
  static const maxAccuracyM = 50.0;
  /// Implied speed above this (m/s, ~250 km/h) between two fixes is treated as a GPS jump.
  static const maxPlausibleSpeedMps = 70.0;
  /// Movement below max(this, 0.5 x accuracy) is treated as GPS noise, not travel.
  static const noiseFloorM = 4.0;
  /// "Weak signal" after this long without an accepted fix (scaled up in battery-saver mode).
  static const weakAfter = Duration(seconds: 20);
  static const lostAfter = Duration(seconds: 60);

  // ---- Route deviation ----
  static const deviationThresholdM = 80.0;
  static const deviationConsecutiveFixes = 3;
  static const deviationMaxAccuracyM = 40.0;
  /// After the user taps "I'm fine, continue" no new deviation alert for this long.
  static const deviationSnooze = Duration(minutes: 5);

  // ---- Progress ----
  static const arrivalRadiusM = 40.0;
  static const arrivalMaxAccuracyM = 30.0;
  static const arrivalConsecutiveFixes = 3;
  static const arrivalDwell = Duration(seconds: 15); // near + accurate this long also counts
  static const stepAdvanceM = 15.0; // a manoeuvre closer than this behind us counts as passed

  // ---- Nearby places (Overpass) ----
  static const nearbyRadiusM = 1000;
  static const nearbyMinMoveM = 400.0;
  static const nearbyMinInterval = Duration(seconds: 45);
  static const nearbyCacheTtl = Duration(minutes: 10);
  static const nearbyMaxResults = 200;

  // ---- Check-in grace ----
  static const checkInGrace = Duration(minutes: 5);
}
