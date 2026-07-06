import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/data/identity_repository.dart';

class CreateTeamScreen extends ConsumerStatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  ConsumerState<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends ConsumerState<CreateTeamScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  // TEAM-7: an optional logo picked before creation, applied right after
  Uint8List? _logoBytes;
  String _logoExt = 'jpg';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 512);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _logoBytes = bytes;
      _logoExt =
          picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
    });
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A team name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(identityRepositoryProvider);
      final teamId = await repo.createTeam(
          name: _name.text.trim(), city: _city.text.trim());
      if (_logoBytes != null) {
        try {
          final url = await repo.uploadAvatar(_logoBytes!, _logoExt);
          await repo.setTeamLogo(teamId, url);
        } catch (_) {/* non-fatal: the logo can be set from the team page */}
      }
      ref.invalidate(myTeamsProvider);
      if (mounted) context.pushReplacement(Routes.teamPage(teamId));
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Create team',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // TEAM-7: the logo can be set at birth, not only from the team page
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage:
                      _logoBytes == null ? null : MemoryImage(_logoBytes!),
                  child: _logoBytes == null
                      ? const Icon(Icons.shield_outlined, size: 32)
                      : null,
                ),
                TextButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label:
                      Text(_logoBytes == null ? 'Add logo (optional)' : 'Change logo'),
                ),
              ],
            ),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Team name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'City (optional)'),
          ),
          const SizedBox(height: 12),
          Text(
            "You'll be added as captain.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: const Text('Create'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
