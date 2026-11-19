import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../providers/providers.dart';

/// Clearly labelled SIMULATED call. It never places or imitates a real telephone call.
class FakeCallScreen extends ConsumerStatefulWidget {
  const FakeCallScreen({super.key});
  @override
  ConsumerState<FakeCallScreen> createState() => _FakeCallState();
}

class _FakeCallState extends ConsumerState<FakeCallScreen> {
  bool _connected = false;
  int _secs = 0;
  Timer? _t;

  void _exit() => context.canPop() ? context.pop() : context.go('/home');

  void _accept() {
    setState(() => _connected = true);
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _secs++));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(callerNameProvider);
    final mm = (_secs ~/ 60).toString().padLeft(2, '0'), ss = (_secs % 60).toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity, margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: RS.amber, borderRadius: BorderRadius.circular(12)),
            child: const Text('SIMULATED CALL. This is not a real phone call.', textAlign: TextAlign.center, style: TextStyle(color: RS.amberText, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          const CircleAvatar(radius: 54, backgroundColor: Color(0xFF2A3B4D), child: Icon(Icons.person, size: 60, color: Colors.white)),
          const SizedBox(height: 20),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_connected ? '$mm:$ss' : 'Incoming call (simulated)', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
            child: Row(mainAxisAlignment: _connected ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween, children: [
              Column(children: [
                IconButton.filled(style: IconButton.styleFrom(backgroundColor: const Color(0xFFC53030), minimumSize: const Size(72, 72)), tooltip: _connected ? 'End simulated call' : 'Decline', onPressed: _exit, icon: const Icon(Icons.call_end, color: Colors.white, size: 32)),
                const SizedBox(height: 6),
                Text(_connected ? 'End' : 'Decline', style: const TextStyle(color: Colors.white70)),
              ]),
              if (!_connected)
                Column(children: [
                  IconButton.filled(style: IconButton.styleFrom(backgroundColor: RS.teal, minimumSize: const Size(72, 72)), tooltip: 'Accept', onPressed: _accept, icon: const Icon(Icons.call, color: Colors.white, size: 32)),
                  const SizedBox(height: 6),
                  const Text('Accept', style: TextStyle(color: Colors.white70)),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
