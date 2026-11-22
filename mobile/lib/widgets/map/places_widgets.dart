import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../providers/nearby_providers.dart';
import '../../services/deviation_detector.dart';
import '../../services/nearby_places_service.dart';
import '../../services/opening_hours.dart';
import '../common.dart';
import 'map_widgets.dart';

String groupLabel(PlaceGroup g) => switch (g) {
      PlaceGroup.emergency => 'Emergency',
      PlaceGroup.commercial => 'Shops & food',
      PlaceGroup.publicFacility => 'Public',
    };

Color _openColor(OpenState s) => switch (s) {
      OpenState.open => const Color(0xFF087F73),
      OpenState.closed => const Color(0xFFC53030),
      OpenState.unknown => const Color(0xFF6B7788),
    };

/// Map-home bottom panel: GPS state, category filters and the nearest OSM places.
class NearbySheet extends StatelessWidget {
  final ScrollController controller;
  final NearbyState nearby;
  final GeoPoint? me;
  final Set<PlaceGroup> groups;
  final ({IconData icon, String text, Color color}) gps;
  final bool survival;
  final void Function(PlaceGroup) onToggleGroup;
  final VoidCallback onRefresh, onPlan, onHavens, onContacts;
  final void Function(NearbyPlace) onTapPlace;
  const NearbySheet({
    super.key, required this.controller, required this.nearby, required this.me, required this.groups, required this.gps,
    required this.survival, required this.onToggleGroup, required this.onRefresh, required this.onPlan, required this.onHavens,
    required this.onContacts, required this.onTapPlace,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final shown = nearby.places.where((p) => groups.contains(p.category.group)).toList();
    if (me != null) {
      shown.sort((a, b) => distanceMeters(me!, a.point).compareTo(distanceMeters(me!, b.point)));
    }
    final list = shown.take(12).toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(250),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: cs.outline.withAlpha(120)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)))),
          Row(children: [
            Expanded(child: PillChip(gps.text, icon: gps.icon, color: gps.color)),
          ]),
          const SizedBox(height: 10),
          FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: onPlan, icon: const Icon(Icons.alt_route), label: const Text('Plan a safer journey')),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Nearby', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            IconButton(onPressed: nearby.loading || me == null ? null : onRefresh, tooltip: 'Refresh nearby places', icon: const Icon(Icons.refresh)),
          ]),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in PlaceGroup.values) FilterChip(label: Text(groupLabel(g)), selected: groups.contains(g), onSelected: (_) => onToggleGroup(g)),
          ]),
          const SizedBox(height: 6),
          if (nearby.loading) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
          if (survival)
            Text('Battery survival mode: nearby places are not refreshed automatically.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          if (nearby.error != null) Text(nearby.error!, style: const TextStyle(color: Color(0xFFC53030), fontSize: 13, fontWeight: FontWeight.w600)),
          if (me == null)
            Text('Waiting for your location to look up places nearby.', style: TextStyle(color: cs.onSurfaceVariant))
          else if (list.isEmpty && !nearby.loading && nearby.fetchedAt != null)
            Text('No places found for the selected categories within about 1 km in OpenStreetMap.', style: TextStyle(color: cs.onSurfaceVariant)),
          for (final p in list)
            _PlaceTile(place: p, distanceM: me == null ? null : distanceMeters(me!, p.point), status: OpeningHours.statusOf(p.openingHours, now), onTap: () => onTapPlace(p)),
          if (nearby.fetchedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Data: OpenStreetMap contributors via Overpass, fetched ${DateFormat('HH:mm').format(nearby.fetchedAt!)}${nearby.fromCache ? ' (cached)' : ''}. '
              'Community-edited and not guaranteed to be current or complete.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          const SectionTitle('Quick actions'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: onHavens, icon: const Icon(Icons.local_hospital_outlined), label: const Text('Safe places')),
            OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: onContacts, icon: const Icon(Icons.contacts_outlined), label: const Text('Trusted contacts')),
          ]),
        ],
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  final NearbyPlace place;
  final double? distanceM;
  final OpenStatus status;
  final VoidCallback onTap;
  const _PlaceTile({required this.place, required this.distanceM, required this.status, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = place.name.isEmpty ? place.category.label : place.name;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: placeColor(place.category.group), shape: BoxShape.circle),
              child: Icon(placeIcon(place.category), color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${place.category.label}${distanceM == null ? '' : '  ·  ${fmtDistance(distanceM!)}'}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                Text(status.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _openColor(status.state))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

void showPlaceDetails(BuildContext context, NearbyPlace p, {required double? distanceM, required DateTime? dataAt, required bool journeyActive, required void Function(String name, GeoPoint point) onNavigate}) {
  final status = OpeningHours.statusOf(p.openingHours, DateTime.now());
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
    builder: (_) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name.isEmpty ? p.category.label : p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('${p.category.label}${distanceM == null ? '' : '  ·  ${fmtDistance(distanceM)} away'}'),
        const SizedBox(height: 10),
        Text(status.label, style: TextStyle(fontWeight: FontWeight.w700, color: _openColor(status.state))),
        if (p.openingHours != null) Text('Published hours: ${p.openingHours}'),
        if (p.address != null) Text('Address: ${p.address}'),
        if (p.phone != null) Text('Phone: ${p.phone}'),
        const SizedBox(height: 10),
        Text(
          'Opening status comes from the hours published in OpenStreetMap, evaluated with your device\'s local time. '
          'It does not confirm the place is operating right now, and holiday or special hours may differ.'
          '${dataAt == null ? '' : ' Data fetched ${DateFormat('HH:mm').format(dataAt)}.'}',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          NavigateButton(name: p.name.isEmpty ? p.category.label : p.name, point: p.point, journeyActive: journeyActive, onNavigate: onNavigate),
          if (p.phone != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: p.phone)),
              icon: const Icon(Icons.call),
              label: const Text('Call'),
            ),
        ]),
      ]),
    ),
  );
}

/// Starts route planning to a place. While a journey is active we must not start a second one,
/// so the place is opened in the phone's maps app instead.
class NavigateButton extends StatelessWidget {
  final String name;
  final GeoPoint point;
  final bool journeyActive;
  final void Function(String name, GeoPoint point) onNavigate;
  const NavigateButton({super.key, required this.name, required this.point, required this.journeyActive, required this.onNavigate});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
        onPressed: () {
          Navigator.of(context).pop();
          if (journeyActive) {
            launchUrl(Uri.parse('geo:${point.lat},${point.lng}?q=${point.lat},${point.lng}(${Uri.encodeComponent(name)})'));
          } else {
            onNavigate(name, point);
          }
        },
        icon: Icon(journeyActive ? Icons.open_in_new : Icons.alt_route),
        label: Text(journeyActive ? 'Open in maps app' : 'Plan route here'),
      );
}
