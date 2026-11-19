import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../providers/providers.dart';

class _AuthForm extends ConsumerStatefulWidget {
  final bool register;
  const _AuthForm({required this.register});
  @override
  ConsumerState<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<_AuthForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController(), _pw = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final auth = ref.read(authProvider.notifier);
      if (widget.register) {
        await auth.register(_name.text.trim(), _email.text.trim(), _pw.text);
      } else {
        await auth.login(_email.text.trim(), _pw.text);
      }
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reg = widget.register;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          const Icon(Icons.shield_outlined, size: 48, color: RS.teal),
          const SizedBox(height: 16),
          Text(reg ? 'Create your account' : 'Welcome back', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(reg ? 'Plan safer journeys with people who can look out for you.' : 'Log in to continue your safer journeys.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 28),
          Form(
            key: _key,
            child: Column(children: [
              if (reg) ...[
                TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null),
                const SizedBox(height: 14),
              ],
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)), validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email'),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pw, obscureText: _hide,
                decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(tooltip: _hide ? 'Show password' : 'Hide password', icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide))),
                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: RS.red, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.error_outline, color: RS.redText), const SizedBox(width: 8), Expanded(child: Text(_error!, style: const TextStyle(color: RS.redText, fontWeight: FontWeight.w600)))])),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(reg ? 'Create account' : 'Log in')),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.go(reg ? '/login' : '/register'), child: Text(reg ? 'I already have an account' : 'Create a new account')),
        ]),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) => const _AuthForm(register: false);
}

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) => const _AuthForm(register: true);
}
