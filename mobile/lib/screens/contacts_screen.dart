import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const _AddContactDialog(),
    );
    if (result != null) {
      try {
        await ref.read(repositoryProvider).addContact(
              result['name'] as String,
              result['phone'] as String,
              result['consent'] as bool,
            );
        ref.invalidate(contactsProvider);
      } catch (e) {
        if (context.mounted) snack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsProvider);
    return PageScaffold(
      title: 'Trusted contacts',
      fab: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add'),
      ),
      child: async.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(e, onRetry: () => ref.invalidate(contactsProvider)),
        data: (list) => list.isEmpty
            ? const EmptyView(
                icon: Icons.group_add_outlined,
                title: 'No trusted contacts',
                message: 'Add people who can check on you during journeys.',
              )
            : ListView(
                padding: pagePadding,
                children: [
                  const DemoBanner(),
                  for (final TrustedContact c in list)
                    RsCard(
                      child: Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person_outline)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text(c.phone),
                                Text(
                                  c.consentToShare
                                      ? 'Agreed to receive location'
                                      : 'Has not agreed to receive location',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Call ${c.name}',
                            icon: const Icon(Icons.call_outlined),
                            onPressed: () =>
                                launchUrl(Uri(scheme: 'tel', path: c.phone)),
                          ),
                          IconButton(
                            tooltip: 'Remove ${c.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await ref
                                  .read(repositoryProvider)
                                  .removeContact(c.id);
                              ref.invalidate(contactsProvider);
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  final _formKey = GlobalKey<FormState>();
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'consent': _consent,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add trusted contact'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
                validator: (v) =>
                    RegExp(r'^\+?[0-9 ]{7,15}$').hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Enter a valid phone number',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v == true),
                title: const Text(
                  'This person agrees to receive my location when I choose to alert them',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
