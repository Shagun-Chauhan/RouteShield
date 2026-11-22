import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../core/api_client.dart';
import '../core/map_config.dart';
import '../models/models.dart';

class GeocodeResult {
  final String name; // display name from the provider
  final GeoPoint point;
  final String? kind; // e.g. "hospital", "road"
  const GeocodeResult(this.name, this.point, this.kind);
}

/// Nominatim-compatible geocoder with: response cache, >=1.1 s spacing between
/// network requests, timeout, and one bounded retry on 429/5xx.
class GeocodingService {
  final _cache = <String, List<GeocodeResult>>{};
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<List<GeocodeResult>> search(String query, {GeoPoint? near}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final key = '${q.toLowerCase()}|${near == null ? '' : '${near.lat.toStringAsFixed(1)},${near.lng.toStringAsFixed(1)}'}';
    final hit = _cache[key];
    if (hit != null) return hit;

    final params = <String, String>{'q': q, 'format': 'jsonv2', 'limit': '6'};
    if (near != null) {
      // Bias (not restrict) results to ~25 km around the user.
      const d = 0.25;
      params['viewbox'] = '${near.lng - d},${near.lat + d},${near.lng + d},${near.lat - d}';
    }
    final uri = Uri.parse('${MapConfig.geocoderUrl}/search').replace(queryParameters: params);

    for (var attempt = 0; attempt < 2; attempt++) {
      final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_last);
      if (!wait.isNegative) await Future.delayed(wait);
      _last = DateTime.now();
      try {
        final r = await http.get(uri, headers: {'User-Agent': MapConfig.geocoderUserAgent, 'Accept-Language': 'en'}).timeout(const Duration(seconds: 8));
        if (r.statusCode == 429 || r.statusCode >= 500) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          throw ApiException(r.statusCode, r.statusCode == 429 ? 'Search is busy. Please wait a moment and try again.' : 'Search service unavailable');
        }
        if (r.statusCode != 200) throw ApiException(r.statusCode, 'Search failed (${r.statusCode})');
        final list = (jsonDecode(r.body) as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return GeocodeResult(
            '${m['display_name']}',
            GeoPoint(double.parse('${m['lat']}'), double.parse('${m['lon']}')),
            m['type'] as String?,
          );
        }).toList();
        _cache[key] = list;
        return list;
      } on SocketException {
        throw NetworkException();
      } on TimeoutException {
        throw NetworkException('The search service took too long to respond');
      } on http.ClientException {
        throw NetworkException();
      }
    }
    return const [];
  }
}
