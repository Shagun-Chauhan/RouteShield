import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editCaller(BuildContext context, WidgetRef ref) async {
    final currentName = ref.read(callerNameProvider);

    // Dialog manages its own controller lifecycle to prevent post-dispose crashes
    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (d) => _EditCallerDialog(initialName: currentName),
    );

    if (newName != null && newName.isNotEmpty) {
      ref.read(callerNameProvider.notifier).state = newName;
      await ref.read(sharedPrefsProvider).setString('caller', newName);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = ref.watch(authProvider);
    final callerName = ref.watch(callerNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: pagePadding,
          children: [
            const DemoBanner(),
            const SizedBox(height: 8),

            // User Info Header Card
            RsCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline,
                      size: 30,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.name ?? 'Traveller',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.email ?? 'No email linked',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Preferences Section
            const SectionTitle('Preferences'),
            RsCard(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      isDark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Dark mode',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      isDark
                          ? 'Using high-contrast dark surface'
                          : 'Using clear light surface',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    value: isDark,
                    onChanged: (v) {
                      final newMode = v ? ThemeMode.dark : ThemeMode.light;
                      ref.read(themeModeProvider.notifier).state = newMode;
                      ref.read(sharedPrefsProvider).setBool('dark', v);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.phone_in_talk_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Simulated caller',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Current: $callerName',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: () => _editCaller(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Journey Management Section
            const SectionTitle('Safety & Records'),
            RsCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.group_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Trusted contacts'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/contacts'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.history, color: theme.colorScheme.primary),
                    title: const Text('Journey history'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/history'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.notifications_none,
                        color: theme.colorScheme.primary),
                    title: const Text('Safety notifications'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/notifications'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // About & System Diagnostics
            const SectionTitle('System & Legal'),
            RsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns_outlined,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Gateway: ${AppConfig.apiBaseUrl}',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'RouteShield provides advisory safety insights to assist travel decisions. It does not replace emergency response authorities. In acute danger, immediately dial 112.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Log Out Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withAlpha(120)),
              ),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _EditCallerDialog extends StatefulWidget {
  final String initialName;
  const _EditCallerDialog({required this.initialName});

  @override
  State<_EditCallerDialog> createState() => _EditCallerDialogState();
}

class _EditCallerDialogState extends State<_EditCallerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Simulated Caller Name'),
      content: TextField(
        controller: _controller,
        maxLength: 30,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Display name',
          hintText: 'e.g. Papa, Hostel Warden',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
