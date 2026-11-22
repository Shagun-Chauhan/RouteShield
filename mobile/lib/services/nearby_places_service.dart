import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../core/api_client.dart';
import '../core/map_config.dart';
import '../core/nav_config.dart';
import '../models/models.dart';

enum PlaceGroup { emergency, commercial, publicFacility }

enum PlaceCategory {
  hospital('Hospital', PlaceGroup.emergency),
  police('Police station', PlaceGroup.emergency),
  pharmacy('Pharmacy', PlaceGroup.emergency),
  clinic('Clinic', PlaceGroup.emergency),
  fireStation('Fire station', PlaceGroup.emergency),
  shop('Shop', PlaceGroup.commercial),
  grocery('Grocery', PlaceGroup.commercial),
  restaurant('Restaurant', PlaceGroup.commercial),
  cafe('Cafe', PlaceGroup.commercial),
  mall('Shopping centre', PlaceGroup.commercial),
  hotel('Hotel', PlaceGroup.commercial),
  fuel('Petrol pump', PlaceGroup.commercial),
  atm('ATM', PlaceGroup.commercial),
  busStop('Bus stop', PlaceGroup.publicFacility),
  railway('Railway station', PlaceGroup.publicFacility),
  metro('Metro station', PlaceGroup.publicFacility),
  toilets('Public toilets', PlaceGroup.publicFacility),
  publicBuilding('Public building', PlaceGroup.publicFacility);

  const PlaceCategory(this.label, this.group);
  final String label;
  final PlaceGroup group;
}

/// Maps OSM tags to a category. Returns null for anything we do not display.
PlaceCategory? classifyOsmTags(Map<String, dynamic> t) {
  switch (t['amenity']) {
    case 'hospital': return PlaceCategory.hospital;
    case 'police': return PlaceCategory.police;
    case 'pharmacy': return PlaceCategory.pharmacy;
    case 'clinic': return PlaceCategory.clinic;
    case 'fire_station': return PlaceCategory.fireStation;
    case 'restaurant': return PlaceCategory.restaurant;
    case 'cafe': return PlaceCategory.cafe;
    case 'fuel': return PlaceCategory.fuel;
    case 'atm': return PlaceCategory.atm;
    case 'toilets': return PlaceCategory.toilets;
    case 'townhall':
    case 'community_centre': return PlaceCategory.publicBuilding;
  }
  switch (t['shop']) {
    case 'supermarket':
    case 'convenience':
    case 'greengrocer': return PlaceCategory.grocery;
    case 'mall':
    case 'department_store': return PlaceCategory.mall;
    case 'general':
    case 'variety_store': return PlaceCategory.shop;
  }
  if (t['tourism'] == 'hotel') return PlaceCategory.hotel;
  if (t['highway'] == 'bus_stop') return PlaceCategory.busStop;
  if (t['railway'] == 'subway_entrance' || (t['railway'] == 'station' && t['station'] == 'subway')) return PlaceCategory.metro;
  if (t['railway'] == 'station') return PlaceCategory.railway;
  return null;
}

class NearbyPlace {
  final String id, name;
  final PlaceCategory category;
  final GeoPoint point;
  final String? openingHours; // raw OSM tag; null when absent
  final String? phone, address; // only when present in OSM
  const NearbyPlace({required this.id, required this.name, required this.category, required this.point, this.openingHours, this.phone, this.address});
}

class NearbyResult {
  final List<NearbyPlace> places;
  final DateTime fetchedAt;
  final bool fromCache;
  const NearbyResult(this.places, this.fetchedAt, {this.fromCache = false});
}

/// Overpass client with a cell-keyed TTL cache. Throttling/debouncing lives in the controller.
class NearbyPlacesService {
  NearbyPlacesService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  final _cache = <String, NearbyResult>{};
  static const _cell = 0.005; // ~550 m

  static String buildQuery(double lat, double lng, int radius) {
    final a = '(around:$radius,${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)})';
    return '[out:json][timeout:20];('
        'nwr["amenity"~"^(hospital|police|pharmacy|clinic|fire_station|restaurant|cafe|fuel|atm|toilets|townhall|community_centre)\$"]$a;'
        'nwr["shop"~"^(supermarket|convenience|greengrocer|mall|department_store|general|variety_store)\$"]$a;'
        'nwr["tourism"="hotel"]$a;'
        'nwr["highway"="bus_stop"]$a;'
        'nwr["railway"~"^(station|subway_entrance)\$"]$a;'
        ');out center tags ${NavConfig.nearbyMaxResults};';
  }

  static String? _address(Map<String, dynamic> t) {
    final parts = [
      [t['addr:housenumber'], t['addr:street']].whereType<String>().join(' '),
      t['addr:suburb'],
      t['addr:city'],
    ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  static List<NearbyPlace> parse(String body) {
    final json = jsonDecode(body);
    final out = <NearbyPlace>[];
    for (final e in (json['elements'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(e as Map);
      final tags = Map<String, dynamic>.from(m['tags'] as Map? ?? const {});
      final cat = classifyOsmTags(tags);
      if (cat == null) continue;
      final center = m['center'] is Map ? Map<String, dynamic>.from(m['center'] as Map) : m;
      final lat = (center['lat'] as num?)?.toDouble(), lon = (center['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      out.add(NearbyPlace(
        id: '${m['type']}/${m['id']}',
        name: '${tags['name'] ?? tags['name:en'] ?? ''}',
        category: cat,
        point: GeoPoint(lat, lon),
        openingHours: tags['opening_hours'] as String?,
        phone: (tags['phone'] ?? tags['contact:phone']) as String?,
        address: _address(tags),
      ));
    }
    return out;
  }

  Future<NearbyResult> fetch(GeoPoint c, {int radius = NavConfig.nearbyRadiusM, bool bypassCache = false}) async {
    final cy = (c.lat / _cell).round(), cx = (c.lng / _cell).round();
    final key = '$cy,$cx,$radius';
    final hit = _cache[key];
    if (!bypassCache && hit != null && DateTime.now().difference(hit.fetchedAt) < NavConfig.nearbyCacheTtl) {
      return NearbyResult(hit.places, hit.fetchedAt, fromCache: true);
    }
    final q = buildQuery(cy * _cell, cx * _cell, radius);
    try {
      final r = await _http
          .post(Uri.parse(MapConfig.overpassUrl), headers: {'User-Agent': MapConfig.overpassUserAgent}, body: {'data': q})
          .timeout(const Duration(seconds: 25));
      if (r.statusCode == 429 || r.statusCode == 504) throw ApiException(r.statusCode, 'The places service is busy. Try again in a minute.');
      if (r.statusCode != 200) throw ApiException(r.statusCode, 'Places lookup failed (${r.statusCode})');
      final res = NearbyResult(parse(r.body), DateTime.now());
      _cache[key] = res;
      if (_cache.length > 30) _cache.remove(_cache.keys.first);
      return res;
    } on SocketException {
      throw NetworkException('No connection: nearby places could not be loaded');
    } on TimeoutException {
      throw NetworkException('The places service took too long to respond');
    } on http.ClientException {
      throw NetworkException('No connection: nearby places could not be loaded');
    } on FormatException {
      throw ApiException(500, 'Unexpected response from the places service');
    }
  }
}
