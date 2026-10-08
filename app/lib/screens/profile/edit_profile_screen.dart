import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../services/api_client.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static const _languages = {'fr': 'Français', 'en': 'English'};
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  String _language = 'fr';
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).update(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            languageCode: _language,
          );
      ref.invalidate(meProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
      context.go('/profile');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return me.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (p) {
        if (!_initialized) {
          _firstName.text = p.firstName;
          _lastName.text = p.lastName;
          _language = _languages.containsKey(p.languageCode) ? p.languageCode : 'fr';
          _initialized = true;
        }
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Modifier le profil', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('ID client : ${p.publicId} (non modifiable)', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _firstName,
                    decoration: const InputDecoration(labelText: 'Prénom'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Prénom requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lastName,
                    decoration: const InputDecoration(labelText: 'Nom'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Nom requis' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration: const InputDecoration(labelText: 'Langue'),
                    items: [for (final e in _languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => _language = v ?? _language,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le téléphone, le pays et la devise se modifient via le support, pour protéger votre compte.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _saving ? null : _save, child: const Text('ENREGISTRER')),
                  TextButton(onPressed: () => context.go('/profile'), child: const Text('Annuler')),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
