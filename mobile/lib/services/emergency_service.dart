import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/navigation_providers.dart';
import '../providers/providers.dart';
import 'emergency_alert.dart';
import 'location_service.dart';

class SosPlan {
  final List<TrustedContact> contacts; // only contacts who consented to receive location
  final LocationFix? fix;
  final bool fixIsLive; // true = from this journey's current GPS stream, false = last stored location
  final String message;
  const SosPlan(this.contacts, this.fix, this.fixIsLive, this.message);
}

/// SOS actions available from the navigation screen.
///
/// The existing backend only exposes `/safety/low-battery-alert`; there is no SOS endpoint, so a
/// server-confirmed SOS cannot be offered yet. This service therefore uses the two actions that
/// work today and are honest about their limits: a pre-filled SMS the USER sends (RouteShield
/// cannot confirm delivery) and the dialler. When a backend SOS endpoint exists, add it here.
class EmergencyService {
  EmergencyService(this._ref);
  final Ref _ref;

  static const emergencyNumber = '112'; // India single emergency number

  Future<SosPlan> prepare() async {
    final journey = _ref.read(activeJourneyProvider);
    var contacts = <TrustedContact>[];
    try {
      final all = await _ref.read(repositoryProvider).contacts();
      contacts = all.where((c) => c.consentToShare && (journey == null || journey.contactIds.isEmpty || journey.contactIds.contains(c.id))).toList();
    } catch (_) {/* offline: continue without contacts, the UI says so */}

    final nav = _ref.read(navigationProvider);
    LocationFix? fix;
    var live = false;
    if (nav.fix != null && nav.fixAt != null) {
      fix = LocationFix(lat: nav.fix!.point.lat, lng: nav.fix!.point.lng, at: nav.fixAt!, accuracy: nav.fix!.accuracyM);
      live = DateTime.now().difference(nav.fixAt!) < const Duration(minutes: 2);
    } else {
      final stored = LocationService.load(_ref.read(sharedPrefsProvider));
      if (stored != null) fix = LocationFix(lat: stored.point.lat, lng: stored.point.lng, at: stored.at);
    }
    return SosPlan(contacts, fix, live, compose(journey, fix, DateTime.now()));
  }

  static String compose(Journey? j, LocationFix? fix, DateTime now) {
    final f = DateFormat('d MMM yyyy, HH:mm');
    final loc = fix == null
        ? 'Location: not available.'
        : 'Last known location: ${fix.osmLink}\nRecorded: ${f.format(fix.at)} (${ageText(now.difference(fix.at))})'
            '${now.difference(fix.at) > staleAfter ? ' - OUT OF DATE, they may have moved' : ''}';
    return 'ROUTESHIELD EMERGENCY\nI need help${j == null ? '' : ' on my journey to ${j.destination}'}.\n$loc\nSent: ${f.format(now)}';
  }

  Future<bool> openSms(SosPlan plan) {
    if (plan.contacts.isEmpty) return Future.value(false);
    final numbers = plan.contacts.map((c) => c.phone).join(',');
    return launchUrl(Uri(scheme: 'sms', path: numbers, queryParameters: {'body': plan.message}));
  }

  Future<bool> callEmergency() => launchUrl(Uri(scheme: 'tel', path: emergencyNumber));
}

final emergencyServiceProvider = Provider<EmergencyService>((ref) => EmergencyService(ref));
