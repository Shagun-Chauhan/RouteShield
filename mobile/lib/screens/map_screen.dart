import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:routeshield/services/journey_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config.dart';
import '../core/map_config.dart';
import '../models/destination.dart';
import '../models/models.dart';
import '../providers/navigation_providers.dart';
import '../providers/nearby_providers.dart';
import '../providers/providers.dart';
import '../providers/survival_providers.dart' show survivalProfileProvider;
import '../services/deviation_detector.dart';
import '../services/live_location.dart';
import '../services/location_service.dart';
import '../services/emergency_service.dart';
import '../services/nearby_places_service.dart';
import '../widgets/common.dart';
import '../widgets/map/map_widgets.dart';
import '../widgets/map/nav_panels.dart';
import '../widgets/map/places_widgets.dart';
import '../widgets/map/sos_sheet.dart';
import '../widgets/map/survival_chip.dart';
import 'routes_screens.dart' show StartJourneySheet;

LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

/// Segment geometry is only usable if the server supplied valid path indices.
bool _hasSegmentGeometry(RouteOption r) =>
    r.segments.isNotEmpty &&
    r.segments.every((s) =>
        s.startIndex != null && s.endIndex != null && s.startIndex! >= 0 && s.endIndex! < r.path.length && s.endIndex! > s.startIndex!);

enum _Mode { home, route, navigating }

/// Map tab. This widget only composes the screen: map layers, floating controls and an adaptive
/// bottom sheet. Navigation, GPS filtering, nearby places and emergency logic live in providers
/// and services (navigation_providers, nearby_providers, emergency_service, ...).
///
/// Overflow note: the previous version put the search bar, banners, five round buttons, a
/// route/journey card and a fixed 70 px footer into ONE Column inside a fixed-height SafeArea.
/// On short screens (or larger text) the sum of those heights exceeded the viewport and the
/// Spacer could not shrink below zero, hence the RenderFlex overflow when a journey started.
/// Now every overlay is either `Positioned` (cannot overflow a Stack) or lives inside a scrollable
/// (the DraggableScrollableSheet / a height-capped scroll view), so content can never overflow.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  final _sheetCtl = DraggableScrollableController();
  final _sheetPx = ValueNotifier<double>(0);
  final _topKey = GlobalKey();
  final _groups = <PlaceGroup>{...PlaceGroup.values};

  bool _ready = false, _showSafety = true, _showHavens = true, _showPlaces = true, _tileFail = false;
  bool _follow = true, _headingUp = false;
  int? _segIdx;
  int _tileErrors = 0;
  double _bodyH = 0;
  String? _sheetKey;
  Timer? _settle;

  // Polyline cache: rebuilt only when route / layer / selection changes, not on every GPS fix.
  RouteOption? _linesRoute;
  bool? _linesSafety;
  int? _linesSeg;
  List<Polyline> _lines = const [];

  @override
  void dispose() {
    _settle?.cancel();
    _sheetCtl.dispose();
    _sheetPx.dispose();
    _map.dispose();
    super.dispose();
  }

  // ---------- map helpers ----------
  void _onTileError() {
    _tileErrors++;
    if (_tileErrors >= 3 && !_tileFail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tileFail = true);
      });
    }
  }

  void _retryTiles() => setState(() {
        _tileErrors = 0;
        _tileFail = false;
      });

  void _zoom(double d) {
    final z = (_map.camera.zoom + d).clamp(MapConfig.minZoom, MapConfig.maxZoom);
    _map.move(_map.camera.center, z);
  }

  double _topH = 0;
  double get _topPx => MediaQuery.paddingOf(context).top + _topH + 16;

  /// Measured after layout (never during it) so camera padding follows the real overlay height.
  void _measureTop() {
    final box = _topKey.currentContext?.findRenderObject();
    final h = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    if ((h - _topH).abs() > 1 && mounted) setState(() => _topH = h);
  }

  /// Centres [p] in the part of the map that is NOT covered by the top overlay or the bottom
  /// sheet, keeping the current zoom (or [zoom] when given). A one-metre-wide bounds is fitted so
  /// flutter_map applies the padding for us; maxZoom pins the zoom level.
  void _followTo(LatLng p, {double? zoom}) {
    if (!_ready || !mounted) return;
    final z = (zoom ?? _map.camera.zoom).clamp(MapConfig.minZoom, MapConfig.maxZoom).toDouble();
    final h = ref.read(navigationProvider).fix?.headingDeg;
    if (_headingUp && h != null) {
      // Heading-up: the map rotates so "ahead" is up. The user is centred on screen in this mode.
      _map.moveAndRotate(p, z, -h);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([p, LatLng(p.latitude + 0.00001, p.longitude + 0.00001)]),
      padding: EdgeInsets.fromLTRB(40, _topPx, 40, _sheetPx.value + 24),
      maxZoom: z,
    ));
  }

  LatLng? _currentPoint() {
    final nav = ref.read(navigationProvider);
    if (nav.active && nav.fix != null) return _ll(nav.fix!.point);
    final raw = ref.read(livePositionProvider).valueOrNull;
    if (raw != null) return LatLng(raw.latitude, raw.longitude);
    final stored = LocationService.load(ref.read(sharedPrefsProvider));
    return stored == null ? null : _ll(stored.point);
  }

  void _toggleOrientation() {
    setState(() => _headingUp = !_headingUp);
    if (!_headingUp) _map.rotate(0);
    final p = _currentPoint();
    if (_headingUp && p != null) _followTo(p);
  }

  void _planTo(String name, GeoPoint point) => context.push('/routes', extra: Destination(name, point));

  void _selectRoute(RouteOption r) {
    final pv = ref.read(routePreviewProvider);
    if (pv == null) return;
    ref.read(routePreviewProvider.notifier).state = RoutePreview(pv.destination, pv.routes, r.id);
    ref.read(selectedRouteProvider.notifier).state = r;
  }

  void _closePreview() {
    ref.read(routePreviewProvider.notifier).state = null;
    ref.read(selectedRouteProvider.notifier).state = null;
  }

  void _startFromPreview(RoutePreview pv, RouteOption r) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => StartJourneySheet(route: r, destination: pv.destination),
      );

  void _recenter() {
    final p = _currentPoint();
    if (p == null) {
      snack(context, 'Waiting for a location fix');
      return;
    }
    setState(() => _follow = true);
    _followTo(p, zoom: math.max(_map.camera.zoom, MapConfig.followZoom));
  }

  void _fitRoute(RouteOption r) {
    if (!_ready || r.path.length < 2) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(r.path.map(_ll).toList()),
      padding: EdgeInsets.fromLTRB(40, _topPx, 40, _sheetPx.value + 24),
    ));
  }

  /// Re-centre after the sheet stops moving so the user marker is never hidden behind it.
  void _onSheetMoved(double extent) {
    _sheetPx.value = extent * _bodyH;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || !_follow) return;
      final p = _currentPoint();
      if (p != null) _followTo(p);
    });
  }

  int? _hitSegment(RouteOption r, LatLng tap) {
    if (!_hasSegmentGeometry(r)) return null;
    const dist = Distance();
    var best = -1;
    var bestM = double.infinity;
    for (var i = 0; i < r.path.length; i++) {
      final m = dist.as(LengthUnit.Meter, tap, _ll(r.path[i]));
      if (m < bestM) {
        bestM = m;
        best = i;
      }
    }
    final metresPerPx = 156543.03 * math.cos(tap.latitudeInRad) / math.pow(2, _map.camera.zoom);
    if (bestM > metresPerPx * 40) return null;
    final idx = r.segments.indexWhere((s) => best >= s.startIndex! && best <= s.endIndex!);
    return idx < 0 ? null : idx;
  }

  List<Polyline> _routeLines(RouteOption r) {
    if (identical(r, _linesRoute) && _linesSafety == _showSafety && _linesSeg == _segIdx) return _lines;
    _linesRoute = r;
    _linesSafety = _showSafety;
    _linesSeg = _segIdx;
    _lines = _buildLines(r);
    return _lines;
  }

  List<Polyline> _buildLines(RouteOption r) {
    if (r.path.length < 2) return const [];
    final geo = _hasSegmentGeometry(r);
    if (!_showSafety) {
      return [Polyline(points: r.path.map(_ll).toList(), strokeWidth: 7, color: rsBlue, borderStrokeWidth: 2, borderColor: Colors.white)];
    }
    if (!geo) {
      // No per-segment geometry from the server: colour the whole route by its overall level.
      return [Polyline(points: r.path.map(_ll).toList(), strokeWidth: 7, color: riskColor(r.riskLevel), borderStrokeWidth: 2, borderColor: Colors.white)];
    }
    return [
      for (var i = 0; i < r.segments.length; i++)
        Polyline(
          points: r.path.sublist(r.segments[i].startIndex!, r.segments[i].endIndex! + 1).map(_ll).toList(),
          strokeWidth: _segIdx == i ? 10 : 7,
          color: riskColor(r.segments[i].riskLevel),
          borderStrokeWidth: 2,
          borderColor: Colors.white,
        ),
    ];
  }

  // ---------- journey actions ----------
  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(c, true), child: Text(yes)),
          ],
        ),
      ) ??
      false;

  Future<void> _finish(Journey j, {required bool cancel}) async {
    final ok = cancel
        ? await _confirm('Cancel this journey?', 'Tracking and check-ins will stop and your contacts will not be updated.', 'Cancel journey')
        : await _confirm('Complete this journey?', 'Only do this if you have arrived or are safe. Tracking and check-in reminders will stop.', 'Complete');
    if (!ok || !mounted) return;
    final summary = ref.read(navigationProvider.notifier).summary(j.destination, cancelled: cancel);
    final err = await ref.read(journeyServiceProvider).finish(j, cancel: cancel);
    if (!mounted) return;
    if (err != null) {
      snack(context, err);
    } else if (cancel) {
      snack(context, 'Journey cancelled.');
    } else {
      _showSummary(summary);
    }
  }

  void _showSummary(JourneySummary s) {
    final mins = s.duration.inMinutes;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Journey complete'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('To ${s.destination}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Time: ${mins < 1 ? 'under a minute' : fmtDuration(s.duration)}'),
          Text('Distance tracked: ${fmtDistance(s.travelledM)} (filtered GPS)'),
          Text(s.arrivedDetected ? 'Arrival was detected by GPS.' : 'You completed this journey before arrival was detected.'),
        ]),
        actions: [FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(c), child: const Text('Done'))],
      ),
    );
  }

  Future<void> _checkIn() async {
    final err = await ref.read(navigationProvider.notifier).checkIn();
    if (!mounted) return;
    snack(context, err ?? 'Checked in. Thank you.');
  }

  void _togglePause() {
    final c = ref.read(navigationProvider.notifier);
    ref.read(navigationProvider).paused ? c.resume() : c.pause();
  }

  void _toggleSheet() {
    if (!_sheetCtl.isAttached || _bodyH == 0) return;
    final expanded = _sheetPx.value / _bodyH > 0.4;
    _sheetCtl.animateTo(expanded ? 0.0 : 1.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // ---------- build ----------
  _Mode _modeOf(RouteOption? route, Journey? journey) =>
      journey != null && route != null ? _Mode.navigating : (route != null ? _Mode.route : _Mode.home);

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(selectedRouteProvider);
    final journey = ref.watch(activeJourneyProvider);
    final havens = ref.watch(havensProvider).valueOrNull ?? const <SafeHaven>[];
    final nearby = ref.watch(nearbyPlacesProvider);
    final access = ref.watch(locationAccessProvider).valueOrNull;
    final gpsError = ref.watch(livePositionProvider.select((a) => a.hasError));
    final survival = ref.watch(survivalProfileProvider.select((p) => p.survival));
    final preview = ref.watch(routePreviewProvider);
    final demo = ref.watch(demoActiveProvider);
    final mode = _modeOf(route, journey);
    final hasRoute = route != null && route.path.length > 1;

    // Journey just started: switch to following the user.
    ref.listen<Journey?>(activeJourneyProvider, (prev, next) {
      if (prev == null && next != null) {
        setState(() {
          _follow = true;
          _segIdx = null;
        });
        final p = _currentPoint();
        if (p != null) _followTo(p, zoom: MapConfig.followZoom);
      }
    });
    ref.listen<RouteOption?>(selectedRouteProvider, (_, r) {
      if (r == null) return;
      setState(() => _segIdx = null);
      if (ref.read(activeJourneyProvider) == null) {
        setState(() => _follow = false);
        _fitRoute(r);
      }
    });
    // Navigation fixes are already filtered (accuracy, jumps, stationary jitter).
    ref.listen<_FixKey>(navigationProvider.select((s) => _FixKey(s.fix?.at, s.fix?.point)), (_, f) {
      final pt = f.point;
      if (pt != null && _follow && _ready) _followTo(_ll(pt));
    });
    ref.listen<AsyncValue<Position>>(livePositionProvider, (_, next) {
      final p = next.valueOrNull;
      if (p == null) return;
      if (ref.read(navigationProvider).active == false && _follow && _ready) _followTo(LatLng(p.latitude, p.longitude));
      if (_showPlaces && p.accuracy <= 100) ref.read(nearbyPlacesProvider.notifier).onLocation(GeoPoint(p.latitude, p.longitude));
    });

    final fallback = _currentPoint() ?? _ll(AppConfig.defaultCenter);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTop());

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(builder: (context, c) {
        _bodyH = c.maxHeight;
        return Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: fallback,
              initialZoom: mode == _Mode.navigating ? MapConfig.followZoom : MapConfig.defaultZoom,
              initialCameraFit: hasRoute && mode == _Mode.route
                  ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(route.path.map(_ll).toList()), padding: const EdgeInsets.fromLTRB(40, 140, 40, 280))
                  : null,
              minZoom: MapConfig.minZoom,
              maxZoom: MapConfig.maxZoom,
              onMapReady: () => _ready = true,
              onPositionChanged: (_, byGesture) {
                if (byGesture && _follow) setState(() => _follow = false);
              },
              onTap: (_, point) {
                if (route == null) return;
                if (preview != null && journey == null) {
                  final mpp = 156543.03 * math.cos(point.latitudeInRad) / math.pow(2, _map.camera.zoom);
                  for (final r in preview.routes) {
                    if (r.id != route.id && distanceToPathMeters(GeoPoint(point.latitude, point.longitude), r.path) < mpp * 30) {
                      _selectRoute(r);
                      return;
                    }
                  }
                }
                final i = _hitSegment(route, point);
                if (i == null) return;
                setState(() => _segIdx = i);
                _showSegment(route.segments[i]);
              },
            ),
            children: [
              TileLayer(
                key: ValueKey(_tileFail),
                urlTemplate: MapConfig.tileUrl,
                userAgentPackageName: MapConfig.userAgentPackage,
                maxNativeZoom: 19,
                errorTileCallback: (_, __, ___) => _onTileError(),
              ),
              if (preview != null && mode == _Mode.route)
                PolylineLayer(polylines: [
                  for (final r in preview.routes)
                    if (r.id != route?.id && r.path.length > 1)
                      Polyline(points: r.path.map(_ll).toList(), strokeWidth: 5, color: const Color(0xFF8795A8).withAlpha(200), borderStrokeWidth: 1.5, borderColor: Colors.white),
                ]),
              if (hasRoute) PolylineLayer(polylines: _routeLines(route)),
              const _AccuracyLayer(),
              if (hasRoute)
                MarkerLayer(markers: [
                  Marker(point: _ll(route.path.last), width: 40, height: 40, alignment: Alignment.topCenter, child: const Icon(Icons.flag_circle, color: Color(0xFF16324F), size: 38)),
                ]),
              if (_showPlaces && !survival)
                MarkerLayer(markers: [
                  for (final p in nearby.places.where((p) => _groups.contains(p.category.group)).take(80))
                    Marker(
                      point: _ll(p.point),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showPlace(p, nearby.fetchedAt),
                        child: PlacePin(p.category),
                      ),
                    ),
                ]),
              if (_showHavens)
                MarkerLayer(markers: [
                  for (final h in havens)
                    Marker(
                      point: _ll(h.location),
                      width: 42,
                      height: 42,
                      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _showHaven(h), child: HavenPin(h.type)),
                    ),
                ]),
              const _UserMarkerLayer(),
            ],
          ),
          _bottomSheet(mode, route, journey, nearby, survival, preview, demo),
          _floatingControls(mode),
          _attribution(journey != null),
          _topOverlay(mode, access, gpsError, survival),
        ]);
      }),
    );
  }

  // ---------- overlays ----------
  Widget _topOverlay(_Mode mode, LocationAccess? access, bool gpsError, bool survival) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _bodyH * 0.45),
            child: SingleChildScrollView(
              child: Column(key: _topKey, mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (mode == _Mode.navigating)
                  _NavTop(
                    onComplete: () {
                      final j = ref.read(activeJourneyProvider);
                      if (j != null) _finish(j, cancel: false);
                    },
                  ),
                if (mode != _Mode.navigating)
                  GestureDetector(
                    onTap: () => context.push('/search'),
                    child: const GlassCard(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [Icon(Icons.search), SizedBox(width: 10), Expanded(child: Text('Plan a safer journey', style: TextStyle(fontWeight: FontWeight.w600)))]),
                    ),
                  ),
                const DemoBanner(),
                if (mode == _Mode.navigating)
                  Consumer(builder: (context, ref, _) {
                    final nav = ref.watch(navigationProvider);
                    final j = ref.read(activeJourneyProvider);
                    return JourneyAlerts(
                      nav: nav,
                      onCheckIn: _checkIn,
                    );
                  }),
                const RerouteCard(),
                const SurvivalChip(),
                if (_tileFail) MapBanner(Icons.cloud_off, 'Map tiles could not be loaded. Check your connection.', action: 'Retry', onTap: _retryTiles),
                if (access == LocationAccess.denied)
                  MapBanner(Icons.location_disabled, 'Location permission is needed to show where you are.', action: 'Allow', onTap: () => ref.invalidate(locationAccessProvider)),
                if (access == LocationAccess.deniedForever)
                  const MapBanner(Icons.location_disabled, 'Location is blocked for RouteShield. Enable it in app settings.', action: 'Settings', onTap: Geolocator.openAppSettings),
                if (access == LocationAccess.serviceOff)
                  MapBanner(Icons.location_off, 'Device location is switched off.', action: 'Turn on', onTap: () async {
                    await Geolocator.openLocationSettings();
                    ref.invalidate(locationAccessProvider);
                  }),
                if (gpsError && access == LocationAccess.granted)
                  MapBanner(Icons.gps_off, 'Could not read your location.', action: 'Retry', onTap: () => ref.invalidate(livePositionProvider)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _floatingControls(_Mode mode) {
    return ValueListenableBuilder<double>(
      valueListenable: _sheetPx,
      builder: (context, sheetPx, _) {
        final avail = _bodyH - sheetPx - _topPx - 12;
        final fit = ((avail + 8) / 56).floor().clamp(1, 6);
        final items = <Widget>[
          RoundBtn(Icons.my_location, 'Centre on me', _recenter, on: _follow),
          RoundBtn(Icons.explore_outlined, _headingUp ? 'Map follows heading (tap for north-up)' : 'North-up (tap to follow heading)', _toggleOrientation, on: _headingUp),
          RoundBtn(Icons.shield_outlined, 'Safety colouring', () => setState(() => _showSafety = !_showSafety), on: _showSafety),
          RoundBtn(Icons.add, 'Zoom in', () => _zoom(1)),
          RoundBtn(Icons.remove, 'Zoom out', () => _zoom(-1)),
          RoundBtn(Icons.store_mall_directory_outlined, 'Nearby places', () => setState(() => _showPlaces = !_showPlaces), on: _showPlaces),
          RoundBtn(Icons.local_hospital_outlined, 'Verified safe places', () => setState(() => _showHavens = !_showHavens), on: _showHavens),
        ].take(fit).toList();
        return Positioned(
          right: 12,
          bottom: sheetPx + 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            verticalDirection: VerticalDirection.up,
            children: [for (var i = 0; i < items.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: items[i])],
          ),
        );
      },
    );
  }

  /// SOS rides on top of the sheet so an expanded sheet can never hide it. The OSM attribution sits
  /// just above the sheet too (it would otherwise be covered by it).
  Widget _attribution(bool journeyActive) {
    return ValueListenableBuilder<double>(
      valueListenable: _sheetPx,
      builder: (context, sheetPx, _) => Positioned(
        left: 12,
        bottom: sheetPx + 8,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (journeyActive) ...[
            SosButton(onTap: () => showSosSheet(context)),
            const SizedBox(height: 8),
          ],
          InkWell(
            onTap: () => launchUrl(Uri.parse(MapConfig.attributionUrl)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withAlpha(220), borderRadius: BorderRadius.circular(8)),
              child: const Text(MapConfig.attributionText, style: TextStyle(fontSize: 11, color: Color(0xFF172B43))),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _bottomSheet(_Mode mode, RouteOption? route, Journey? journey, NearbyState nearby, bool survival, RoutePreview? preview, bool demo) {
    final h = _bodyH;
    if (h == 0) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6).toDouble();
    final inset = MediaQuery.paddingOf(context).bottom;
    final collapsedPx = (mode == _Mode.navigating ? 170.0 : 130.0) * scale + inset;
    final minFrac = (collapsedPx / h).clamp(0.12, 0.45).toDouble();
    final maxFrac = math.max(minFrac + 0.1, mode == _Mode.navigating ? 0.62 : 0.55).clamp(0.2, 0.9).toDouble();
    final key = '${mode.name}-${minFrac.toStringAsFixed(3)}-${maxFrac.toStringAsFixed(2)}';
    if (_sheetKey != key) {
      _sheetKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sheetPx.value = minFrac * _bodyH;
      });
    }

    return Positioned.fill(
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: (n) {
          _onSheetMoved(n.extent);
          return false;
        },
        child: DraggableScrollableSheet(
          key: ValueKey(key),
          controller: _sheetCtl,
          initialChildSize: minFrac,
          minChildSize: minFrac,
          maxChildSize: maxFrac,
          snap: true,
          builder: (context, sc) {
            if (mode == _Mode.navigating && route != null && journey != null) {
              return Consumer(builder: (context, ref, _) {
                final nav = ref.watch(navigationProvider);
                final expanded = _bodyH > 0 && (_sheetPx.value / _bodyH) > (minFrac + maxFrac) / 2;
                return ActiveNavSheet(
                  controller: sc,
                  nav: nav,
                  route: route,
                  journey: journey,
                  expanded: expanded,
                  facilities: _facilities(ref, nav),
                  contactsLine: _contactsLine(ref, journey),
                  onToggle: _toggleSheet,
                  onPauseResume: _togglePause,
                  onEnd: () => _finish(journey, cancel: false),
                  onCancel: () => _finish(journey, cancel: true),
                  onOpenDetails: () => context.push('/journey'),
                  onHavens: () => context.push('/havens'),
                  onPlan: () => context.push('/plan'),
                );
              });
            }
            if (mode == _Mode.route && route != null && preview != null) {
              return RoutePreviewSheet(
                controller: sc,
                preview: preview,
                route: route,
                sample: demo || route.isDemo,
                onSelect: _selectRoute,
                onStart: () => _startFromPreview(preview, route),
                onClose: _closePreview,
              );
            }
            if (mode == _Mode.route && route != null) {
              return RoutePanel(route, segmentsTappable: _hasSegmentGeometry(route), controller: sc);
            }
            return Consumer(builder: (context, ref, _) {
            final gps = _homeGps(ref);
            final me = _currentPoint();
            return NearbySheet(
              controller: sc,
              nearby: nearby,
              me: me == null ? null : GeoPoint(me.latitude, me.longitude),
              groups: _groups,
              gps: gps,
              survival: survival,
              onToggleGroup: (g) => setState(() => _groups.contains(g) ? _groups.remove(g) : _groups.add(g)),
              onRefresh: () {
                if (me != null) ref.read(nearbyPlacesProvider.notifier).refresh(GeoPoint(me.latitude, me.longitude));
              },
              onPlan: () => context.push('/search'),
              onHavens: () => context.push('/havens'),
              onContacts: () => context.push('/contacts'),
              onTapPlace: (p) {
                setState(() => _follow = false);
                if (_ready) _map.move(_ll(p.point), math.max(_map.camera.zoom, 17));
                _showPlace(p, nearby.fetchedAt);
              },
            );
            });
          },
        ),
      ),
    );
  }

  /// Nearest emergency facilities from OSM (hospital, police, ...) plus verified safe havens.
  List<FacilityRow> _facilities(WidgetRef ref, NavState nav) {
    final me = nav.fix?.point ?? _currentPoint().let((p) => GeoPoint(p.latitude, p.longitude));
    if (me == null) return const [];
    final rows = <FacilityRow>[];
    for (final p in ref.watch(nearbyPlacesProvider).places.where((p) => p.category.group == PlaceGroup.emergency)) {
      rows.add(FacilityRow(p.name.isEmpty ? p.category.label : p.name, p.category.label, distanceMeters(me, p.point), () => _focus(p.point)));
    }
    for (final h in ref.watch(havensProvider).valueOrNull ?? const <SafeHaven>[]) {
      rows.add(FacilityRow(h.name.isEmpty ? 'Safe haven' : h.name, 'RouteShield safe haven', distanceMeters(me, h.location), () => _focus(h.location)));
    }
    rows.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return rows.take(3).toList();
  }

  void _focus(GeoPoint p) {
    setState(() => _follow = false);
    if (_ready) _map.move(_ll(p), math.max(_map.camera.zoom, 16));
    if (_sheetCtl.isAttached) _sheetCtl.animateTo(0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  String _contactsLine(WidgetRef ref, Journey j) {
    final all = ref.watch(contactsProvider).valueOrNull;
    if (all == null) return 'Contact list not loaded yet.';
    final chosen = all.where((c) => j.contactIds.contains(c.id)).toList();
    if (chosen.isEmpty) return 'No trusted contacts selected for this journey. SOS can still call ${EmergencyService.emergencyNumber}.';
    final ok = chosen.where((c) => c.consentToShare).map((c) => c.name).toList();
    final noConsent = chosen.length - ok.length;
    return '${ok.isEmpty ? 'None of the selected contacts has agreed to receive your location' : 'Can receive your location: ${ok.join(', ')}'}'
        '${noConsent > 0 ? ' ($noConsent without consent are skipped)' : ''}. '
        'Messages are only prepared when you press SOS or share; RouteShield cannot confirm that they were sent.';
  }

  ({IconData icon, String text, Color color}) _homeGps(WidgetRef ref) {
    final access = ref.watch(locationAccessProvider).valueOrNull;
    final raw = ref.watch(livePositionProvider);
    if (access != null && access != LocationAccess.granted) {
      return (icon: Icons.gps_off, text: 'Location unavailable', color: const Color(0xFFC53030));
    }
    final p = raw.valueOrNull;
    if (p == null) return (icon: Icons.gps_not_fixed, text: 'Waiting for GPS fix', color: const Color(0xFF6B7788));
    if (p.accuracy > MapConfig.poorAccuracyM) {
      return (icon: Icons.gps_not_fixed, text: 'GPS accuracy low (±${p.accuracy.round()} m)', color: const Color(0xFFB7791F));
    }
    return (icon: Icons.gps_fixed, text: 'Live GPS  ±${p.accuracy.round()} m', color: const Color(0xFF087F73));
  }

  // ---------- detail sheets ----------
  void _showSegment(SegmentAssessment s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (ctx, sc) => SegmentPanel(s, controller: sc, onClose: () => Navigator.pop(ctx)),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _segIdx = null);
    });
  }

  void _showPlace(NearbyPlace p, DateTime? fetchedAt) {
    final me = _currentPoint();
    final d = me == null ? null : distanceMeters(GeoPoint(me.latitude, me.longitude), p.point);
    showPlaceDetails(context, p, distanceM: d, dataAt: fetchedAt, journeyActive: ref.read(activeJourneyProvider) != null, onNavigate: _planTo);
  }

  void _showHaven(SafeHaven h) {
    final me = _currentPoint();
    final d = me != null ? Geolocator.distanceBetween(me.latitude, me.longitude, h.location.lat, h.location.lng) : h.distanceM;
    final status = switch (h.openNow) {
      true => 'Open now (according to published hours)',
      false => 'Closed now (according to published hours)',
      null => 'Hours unavailable',
    };
    final kind = switch (h.type) { 'hospital' => 'Hospital', 'police' => 'Police station', _ => 'Public place' };
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      builder: (_) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.paddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(h.name.isEmpty ? kind : h.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('$kind  ·  ${fmtDistance(d)} away'),
          const SizedBox(height: 10),
          Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (h.hours != null) Text(h.hours!),
          const SizedBox(height: 10),
          Text(
            h.isDemo ? 'Sample data, not a real place.' : 'Published listing data. Opening status is not independently verified in real time.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 12),
          NavigateButton(name: h.name.isEmpty ? kind : h.name, point: h.location, journeyActive: ref.read(activeJourneyProvider) != null, onNavigate: _planTo),
        ]),
      ),
    );
  }
}

/// Equality wrapper so the follow listener fires once per accepted fix.
class _FixKey {
  final DateTime? at;
  final GeoPoint? point;
  const _FixKey(this.at, this.point);
  @override
  bool operator ==(Object o) => o is _FixKey && o.at == at;
  @override
  int get hashCode => at.hashCode;
}

/// Current-or-last-known position for the layers below. Watches only position data, so GPS
/// updates rebuild just these two small layers, not the whole map screen.
({GeoPoint? p, double? acc, double? heading, bool stale}) _userSnapshot(WidgetRef ref) {
  final (active, fix) = ref.watch(navigationProvider.select((s) => (s.active, s.fix)));
  final raw = ref.watch(livePositionProvider).valueOrNull;
  if (active && fix != null) return (p: fix.point, acc: fix.accuracyM, heading: fix.headingDeg, stale: false);
  if (raw != null) {
    return (
      p: GeoPoint(raw.latitude, raw.longitude),
      acc: raw.accuracy,
      heading: (raw.heading >= 0 && raw.speed > 0.5) ? raw.heading : null,
      stale: false,
    );
  }
  final last = LocationService.load(ref.read(sharedPrefsProvider));
  // Last known position, not a current fix: drawn grey, without an accuracy circle.
  return (p: last?.point, acc: null, heading: null, stale: last != null);
}

class _AccuracyLayer extends ConsumerWidget {
  const _AccuracyLayer();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = _userSnapshot(ref);
    if (u.p == null || u.acc == null || u.stale) return const SizedBox.shrink();
    return CircleLayer(circles: [
      CircleMarker(point: _ll(u.p!), radius: u.acc!, useRadiusInMeter: true, color: rsBlue.withAlpha(30), borderColor: rsBlue.withAlpha(90), borderStrokeWidth: 1),
    ]);
  }
}

class _UserMarkerLayer extends ConsumerWidget {
  const _UserMarkerLayer();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = _userSnapshot(ref);
    if (u.p == null) return const SizedBox.shrink();
    return MarkerLayer(markers: [Marker(point: _ll(u.p!), width: 44, height: 44, child: UserMarker(heading: u.heading, stale: u.stale))]);
  }
}

/// Top navigation banner (watches navigation state itself).
class _NavTop extends ConsumerWidget {
  final VoidCallback onComplete;
  const _NavTop({required this.onComplete});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);
    if (nav.arrived && !nav.arrivalDismissed) {
      return ArrivalCard(onComplete: onComplete, onContinue: ref.read(navigationProvider.notifier).continueTracking);
    }
    return NavBanner(nav: nav);
  }
}

extension _Let<T> on T? {
  R? let<R>(R Function(T) f) => this == null ? null : f(this as T);
}
