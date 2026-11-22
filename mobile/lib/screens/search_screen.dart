import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/map_config.dart';
import '../models/destination.dart';
import '../providers/providers.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../widgets/common.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchState();
}

class _SearchState extends ConsumerState<SearchScreen> {
  final _c = TextEditingController();
  Timer? _debounce;
  List<GeocodeResult>? _results;
  bool _loading = false;
  String? _err, _lastQuery;
  int _seq = 0; // ignore stale responses

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    if (!MapConfig.geocoderAutocomplete) return; // public Nominatim forbids search-as-you-type
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(v));
  }

  Future<void> _search(String text) async {
    final q = text.trim();
    if (q.length < 2) {
      setState(() => _err = 'Enter at least 2 characters');
      return;
    }
    final my = ++_seq;
    setState(() {
      _loading = true;
      _err = null;
      _lastQuery = q;
    });
    try {
      final near = LocationService.load(ref.read(sharedPrefsProvider))?.point;
      final r = await ref.read(geocoderProvider).search(q, near: near);
      if (!mounted || my != _seq) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _results = null;
        _loading = false;
        _err = '$e';
      });
    }
  }

  void _choose(Destination d) {
    final p = ref.read(sharedPrefsProvider);
    final recent = (p.getStringList('recent') ?? []).where((e) => e != d.label).toList()..insert(0, d.label);
    p.setStringList('recent', recent.take(5).toList());
    context.push('/routes', extra: d);
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.read(sharedPrefsProvider).getStringList('recent') ?? [];
    final cs = Theme.of(context).colorScheme;
    return PageScaffold(
      title: 'Where to?',
      child: ListView(padding: pagePadding, children: [
        TextField(
          controller: _c,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            labelText: 'Destination (place, address or landmark)',
            prefixIcon: const Icon(Icons.place_outlined),
            suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => _search(_c.text)),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: LoadingView(message: 'Searching...')),
        if (_err != null)
          RsCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_err!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                TextButton(onPressed: () => _search(_c.text), child: const Text('Try again')),
                if (_c.text.trim().length >= 2) TextButton(onPressed: () => _choose(Destination(_c.text.trim())), child: const Text('Use text as typed')),
              ]),
              Text('"Use text as typed" lets the RouteShield server look the place up itself; the exact point is not confirmed.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        if (!_loading && _results != null && _results!.isEmpty)
          EmptyView(icon: Icons.search_off, title: 'No places found', message: 'Nothing matched "$_lastQuery". Try a nearby landmark or a fuller address.'),
        if (!_loading && _results != null)
          for (final r in _results!)
            RsCard(
              onTap: () => _choose(Destination(r.name.split(',').take(2).join(',').trim(), r.point)),
              child: Row(children: [
                const Icon(Icons.place),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name.split(',').first, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ]),
            ),
        if (_results == null && !_loading && _err == null) ...[
          if (recent.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(icon: Icons.travel_explore, title: 'No recent destinations', message: 'Search for a place, then choose a result to compare routes.'))
          else ...[
            const SectionTitle('Recent'),
            for (final r in recent)
              RsCard(
                onTap: () {
                  _c.text = r;
                  _search(r);
                },
                child: Row(children: [const Icon(Icons.history), const SizedBox(width: 12), Expanded(child: Text(r))]),
              ),
          ],
        ],
      ]),
    );
  }
}
