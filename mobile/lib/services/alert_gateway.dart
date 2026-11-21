import '../core/api_client.dart';
import 'emergency_alert.dart';

typedef JsonPost = Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> body);

/// ADAPT: the only line that depends on your ApiClient. I have not seen that
/// file; change `.post(...)` to whatever your client exposes (it must send the
/// user's auth token, return decoded JSON, and throw on non-2xx).
JsonPost jsonPostFor(ApiClient api) =>
    (path, body) async => Map<String, dynamic>.from(await (api as dynamic).post(path, body) as Map);

class GatewayResult {
  const GatewayResult({this.accepted = 0, this.failed = 0, this.total = 0, this.duplicate = false, this.errorCode});
  final int accepted, failed, total;
  final bool duplicate;
  final String? errorCode;
}

/// Talks to YOUR backend. The backend looks up the user's contacts itself and
/// holds the SMS provider credentials; the app never sends phone numbers or
/// message text, so the endpoint can't be abused as an SMS relay.
class AlertGateway {
  AlertGateway(this._post);
  final JsonPost _post;
  static const path = '/safety/low-battery-alert';

  Future<GatewayResult> submit(EmergencyAlertRecord r, {required int threshold, required int tzOffsetMinutes}) async {
    final j = await _post(path, {
      'episodeId': r.id,
      'batteryLevel': r.battery,
      'threshold': threshold,
      'capturedAt': r.createdAt.toUtc().toIso8601String(),
      'tzOffsetMinutes': tzOffsetMinutes,
      'locationStale': r.locationStale,
      if (r.fix != null)
        'location': {
          'lat': r.fix!.lat,
          'lng': r.fix!.lng,
          'recordedAt': r.fix!.at.toUtc().toIso8601String(),
          if (r.fix!.accuracy != null) 'accuracyM': r.fix!.accuracy,
        },
    });
    return GatewayResult(
      accepted: (j['accepted'] as num?)?.toInt() ?? 0,
      failed: (j['failed'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      duplicate: j['duplicate'] == true,
      errorCode: j['errorCode'] as String?,
    );
  }
}
