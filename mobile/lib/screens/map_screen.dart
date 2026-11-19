import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import '../core/config.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

Color _riskColor(String level) => switch (level) {
      'low' => const Color(0xFF087F73),
      'moderate' => const Color(0xFFB7791F),
      'high' => const Color(0xFFC53030),
      _ => const Color(0xFF6B7788),
    };

gm.LatLng _ll(GeoPoint p) => gm.LatLng(p.lat, p.lng);

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(selectedRouteProvider);
    final havens = ref.watch(havensProvider).valueOrNull ?? const <SafeHaven>[];
    final center = route != null && route.path.isNotEmpty ? route.path.first : AppConfig.defaultCenter;
    final markers = <gm.Marker>{
      for (final h in havens)
        gm.Marker(
          markerId: gm.MarkerId('${h.type}-${h.name}'), position: _ll(h.location),
          infoWindow: gm.InfoWindow(title: h.name, snippet: h.isDemo ? 'Demo place' : h.type),
          icon: gm.BitmapDescriptor.defaultMarkerWithHue(h.type == 'hospital' ? gm.BitmapDescriptor.hueRed : gm.BitmapDescriptor.hueAzure),
        ),
    };
    final lines = <gm.Polyline>{
      if (route != null && route.path.length > 1)
        gm.Polyline(polylineId: gm.PolylineId(route.id), points: route.path.map(_ll).toList(), width: 6, color: _riskColor(route.riskLevel)),
    };
    return Scaffold(
      body: Stack(children: [
        gm.GoogleMap(
          initialCameraPosition: gm.CameraPosition(target: _ll(center), zoom: 13),
          markers: markers, polylines: lines, zoomControlsEnabled: false, myLocationButtonEnabled: false, mapToolbarEnabled: false,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              GestureDetector(
                onTap: () => context.push('/search'),
                child: const GlassCard(child: Row(children: [Icon(Icons.search), SizedBox(width: 10), Expanded(child: Text('Plan a safer journey', style: TextStyle(fontWeight: FontWeight.w600)))])),
              ),
              const SizedBox(height: 8),
              const DemoBanner(),
              const Spacer(),
              if (route != null)
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${route.label} route', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [RiskBadge(route.riskLevel), ConfidenceBadge(route.confidenceLevel)]),
                  ]),
                ),
              const SizedBox(height: 70),
            ]),
          ),
        ),
      ]),
    );
  }
}
