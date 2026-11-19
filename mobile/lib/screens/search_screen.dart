import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchState();
}

class _SearchState extends ConsumerState<SearchScreen> {
  final _c = TextEditingController();
  String? _err;

  void _go(String dest) {
    final d = dest.trim();
    if (d.length < 2) {
      setState(() => _err = 'Enter a destination');
      return;
    }
    final p = ref.read(sharedPrefsProvider);
    final recent = (p.getStringList('recent') ?? []).where((e) => e != d).toList()..insert(0, d);
    p.setStringList('recent', recent.take(5).toList());
    context.push('/routes', extra: d);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.read(sharedPrefsProvider).getStringList('recent') ?? [];
    return PageScaffold(
      title: 'Where to?',
      child: ListView(padding: pagePadding, children: [
        TextField(
          controller: _c, autofocus: true, textInputAction: TextInputAction.search, onSubmitted: _go,
          decoration: InputDecoration(labelText: 'Destination', errorText: _err, prefixIcon: const Icon(Icons.place_outlined), suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.arrow_forward), onPressed: () => _go(_c.text))),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => _go(_c.text), child: const Text('Compare routes')),
        if (recent.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(icon: Icons.travel_explore, title: 'No recent destinations', message: 'Places you search for will appear here.'))
        else ...[
          const SectionTitle('Recent'),
          for (final r in recent) RsCard(onTap: () => _go(r), child: Row(children: [const Icon(Icons.history), const SizedBox(width: 12), Expanded(child: Text(r))])),
        ],
      ]),
    );
  }
}
