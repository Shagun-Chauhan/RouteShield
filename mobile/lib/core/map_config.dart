/// Central OpenStreetMap tile configuration.
///
/// Override at build time, e.g.
///   flutter run --dart-define=OSM_TILE_URL=https://tiles.example.com/{z}/{x}/{y}.png
///
/// IMPORTANT: tile.openstreetmap.org is a community service with a strict usage
/// policy (no heavy/bulk use, valid User-Agent, attribution required). It is fine
/// for development and light use. For production, point OSM_TILE_URL at a hosted
/// provider (MapTiler, Stadia, Thunderforest, self-hosted) and keep any API key
/// in --dart-define or behind your backend, never in source control.
class MapConfig {
  static const tileUrl = String.fromEnvironment(
    'OSM_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Must be your real application id so the tile provider can identify you.
  static const userAgentPackage = String.fromEnvironment(
    'OSM_USER_AGENT_PACKAGE',
    defaultValue: 'com.example.routeshield',
  );

  static const attributionText = '© OpenStreetMap contributors';
  static const attributionUrl = 'https://www.openstreetmap.org/copyright';

  static const minZoom = 3.0;
  static const maxZoom = 19.0;
  static const defaultZoom = 13.0;
  static const followZoom = 16.0;

  /// GPS fixes worse than this (metres) are flagged as inaccurate.
  static const poorAccuracyM = 100.0;

  // ---- Geocoding (Nominatim-compatible) ----
  // Public nominatim.openstreetmap.org: max 1 request/second, identifying User-Agent,
  // and NO search-as-you-type. Search therefore runs on submit unless you point
  // GEOCODER_URL at your own/hosted instance and set GEOCODER_AUTOCOMPLETE=true.
  static const geocoderUrl = String.fromEnvironment('GEOCODER_URL', defaultValue: 'https://nominatim.openstreetmap.org');
  static const geocoderAutocomplete = bool.fromEnvironment('GEOCODER_AUTOCOMPLETE', defaultValue: false);
  static const geocoderUserAgent = String.fromEnvironment('GEOCODER_USER_AGENT', defaultValue: 'RouteShield/0.1 (contact: set-GEOCODER_USER_AGENT)');

  // ---- Nearby places (Overpass-compatible) ----
  // The public overpass-api.de instance is shared infrastructure: keep request volume low
  // (the app throttles + caches) and prefer your own instance or a backend proxy in production:
  //   --dart-define=OVERPASS_URL=https://overpass.example.com/api/interpreter
  static const overpassUrl = String.fromEnvironment('OVERPASS_URL', defaultValue: 'https://overpass-api.de/api/interpreter');
  static const overpassUserAgent = String.fromEnvironment('OVERPASS_USER_AGENT', defaultValue: 'RouteShield/0.1 (contact: set-OVERPASS_USER_AGENT)');

  // ---- Tile caching ----
  // flutter_map's default NetworkTileProvider keeps tiles in memory only. Persistent tile caching
  // needs an extra package (e.g. flutter_map_cache) which this project does not depend on yet.
}
