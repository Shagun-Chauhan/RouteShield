import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../providers/navigation_providers.dart';
import '../../services/nearby_places_service.dart';

Color riskColor(String level) => switch (level) {
      'low' => const Color(0xFF087F73),
      'moderate' => const Color(0xFFB7791F),
      'high' => const Color(0xFFC53030),
      _ => const Color(0xFF6B7788), // unknown is grey, never green
    };

const rsBlue = Color(0xFF1B4C94);
const sosRed = Color(0xFFD32F2F);

String fmtDistance(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1)} km' : '${(m / 10).round() * 10} m';

String fmtDuration(Duration d) {
  final mins = (d.inSeconds / 60).ceil();
  if (mins < 60) return '$mins min';
  return '${mins ~/ 60} h ${mins % 60} min';
}

String fmtClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Icon for a routing-provider manoeuvre (OSRM type/modifier vocabulary).
IconData maneuverIcon(RouteStep? s) {
  if (s == null) return Icons.navigation;
  final type = (s.maneuver ?? '').toLowerCase(), mod = (s.modifier ?? '').toLowerCase();
  if (type == 'arrive') return Icons.flag;
  if (type.contains('roundabout') || type == 'rotary') return Icons.roundabout_left;
  return switch (mod) {
    'left' => Icons.turn_left,
    'right' => Icons.turn_right,
    'slight left' => Icons.turn_slight_left,
    'slight right' => Icons.turn_slight_right,
    'sharp left' => Icons.turn_sharp_left,
    'sharp right' => Icons.turn_sharp_right,
    'uturn' => Icons.u_turn_left,
    'straight' => Icons.straight,
    _ => Icons.navigation,
  };
}

class RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool on;
  const RoundBtn(this.icon, this.tip, this.onTap, {super.key, this.on = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tip,
      child: Tooltip(
        message: tip,
        child: Material(
          color: on ? cs.primary : cs.surface,
          elevation: 3,
          shadowColor: Colors.black38,
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 48, height: 48, child: Icon(icon, color: on ? cs.onPrimary : cs.onSurface))),
        ),
      ),
    );
  }
}

/// Always-visible emergency button. Large touch target, text label (not colour alone).
class SosButton extends StatelessWidget {
  final VoidCallback onTap;
  const SosButton({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Emergency SOS',
        child: Material(
          color: sosRed,
          elevation: 4,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: const SizedBox(
              height: 52,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sos, color: Colors.white),
                  SizedBox(width: 8),
                  Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class MapBanner extends StatelessWidget {
  final IconData icon;
  final String text, action;
  final VoidCallback? onTap;
  final Color? tint;
  const MapBanner(this.icon, this.text, {super.key, this.action = '', this.onTap, this.tint});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: (tint ?? cs.surface).withAlpha(240),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withAlpha(150)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        if (action.isNotEmpty && onTap != null) TextButton(onPressed: onTap, child: Text(action)),
      ]),
    );
  }
}

class PillChip extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color? color;
  const PillChip(this.text, {super.key, this.icon, this.color});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withAlpha(70))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 15, color: c), const SizedBox(width: 5)],
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c))),
      ]),
    );
  }
}

class UserMarker extends StatelessWidget {
  final double? heading;
  final bool stale; // true = last known position, not a current fix
  const UserMarker({super.key, this.heading, this.stale = false});
  @override
  Widget build(BuildContext context) {
    if (heading == null || stale) {
      return Center(child: Container(width: 22, height: 22, decoration: BoxDecoration(color: stale ? const Color(0xFF8795A8) : rsBlue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black38)])));
    }
    return Transform.rotate(angle: heading! * math.pi / 180, child: const Icon(Icons.navigation, color: rsBlue, size: 38, shadows: [Shadow(blurRadius: 6, color: Colors.black38)]));
  }
}

class HavenPin extends StatelessWidget {
  final String type;
  const HavenPin(this.type, {super.key});
  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      'hospital' => (const Color(0xFFC53030), Icons.local_hospital),
      'police' => (rsBlue, Icons.local_police),
      _ => (const Color(0xFF087F73), Icons.verified_user),
    };
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)]),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

IconData placeIcon(PlaceCategory c) => switch (c) {
      PlaceCategory.hospital => Icons.local_hospital,
      PlaceCategory.police => Icons.local_police,
      PlaceCategory.pharmacy => Icons.local_pharmacy,
      PlaceCategory.clinic => Icons.medical_services,
      PlaceCategory.fireStation => Icons.fire_truck,
      PlaceCategory.shop => Icons.store,
      PlaceCategory.grocery => Icons.shopping_basket,
      PlaceCategory.restaurant => Icons.restaurant,
      PlaceCategory.cafe => Icons.local_cafe,
      PlaceCategory.mall => Icons.shopping_bag,
      PlaceCategory.hotel => Icons.hotel,
      PlaceCategory.fuel => Icons.local_gas_station,
      PlaceCategory.atm => Icons.atm,
      PlaceCategory.busStop => Icons.directions_bus,
      PlaceCategory.railway => Icons.train,
      PlaceCategory.metro => Icons.subway,
      PlaceCategory.toilets => Icons.wc,
      PlaceCategory.publicBuilding => Icons.account_balance,
    };

Color placeColor(PlaceGroup g) => switch (g) {
      PlaceGroup.emergency => const Color(0xFFC53030),
      PlaceGroup.commercial => const Color(0xFF8A5A00),
      PlaceGroup.publicFacility => const Color(0xFF3B5B8C),
    };

class PlacePin extends StatelessWidget {
  final PlaceCategory category;
  const PlacePin(this.category, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: placeColor(category.group), border: Border.all(color: Colors.white, width: 1.5), boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)]),
        child: Icon(placeIcon(category), color: Colors.white, size: 16),
      );
}

/// Honest, short wording for the GPS state (current vs last-known).
({IconData icon, String text, Color color}) gpsDescription(NavState s) {
  final f = s.fix;
  final age = s.fixAt == null ? null : DateTime.now().difference(s.fixAt!);
  switch (s.gps) {
    case GpsStatus.good:
      return (icon: Icons.gps_fixed, text: 'Live GPS${f == null ? '' : '  ±${f.accuracyM.round()} m'}', color: const Color(0xFF087F73));
    case GpsStatus.quiet:
      return (
        icon: Icons.gps_not_fixed,
        text: age == null ? 'No GPS update yet' : 'Last known position, ${age.inMinutes < 1 ? '${age.inSeconds}s' : '${age.inMinutes} min'} ago',
        color: const Color(0xFFB7791F)
      );
    case GpsStatus.poor:
      return (icon: Icons.gps_not_fixed, text: 'GPS accuracy low${s.rawAccuracyM == null ? '' : ' (±${s.rawAccuracyM!.round()} m)'}', color: const Color(0xFFB7791F));
    case GpsStatus.unavailable:
      return (icon: Icons.gps_off, text: 'GPS unavailable. Showing last known position', color: const Color(0xFFC53030));
    case GpsStatus.waiting:
      return (icon: Icons.gps_not_fixed, text: 'Waiting for GPS fix', color: const Color(0xFF6B7788));
  }
}
