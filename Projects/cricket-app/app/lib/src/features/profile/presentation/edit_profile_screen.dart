import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../identity/data/identity_repository.dart';
import '../../identity/presentation/initials_avatar.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late final TextEditingController _bowling;
  late final TextEditingController _handle;
  late final bool _hasHandle; // MISS-5: pre-handle accounts can finally set one
  String? _batting; // 'right' | 'left'
  String? _role; // batter | bowler | all_rounder | keeper
  String? _photoUrl;
  bool _busy = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = ref.read(myProfileProvider).value ?? const {};
    _name = TextEditingController(text: (p['display_name'] as String?) ?? '');
    _phone = TextEditingController(text: (p['phone'] as String?) ?? '');
    _city = TextEditingController(text: (p['city'] as String?) ?? '');
    _bowling = TextEditingController(text: (p['bowling_style'] as String?) ?? '');
    _handle = TextEditingController(text: (p['handle'] as String?) ?? '');
    _hasHandle = (p['handle'] as String?)?.isNotEmpty ?? false;
    _batting = p['batting_style'] as String?;
    _role = p['playing_role'] as String?;
    _photoUrl = p['photo_url'] as String?;
  }

  Future<void> _changePhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024);
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _error = null; // PROF-4: a failed upload error is not sticky
    });
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last;
      final repo = ref.read(identityRepositoryProvider);
      final url = await repo.uploadAvatar(bytes, ext);
      await repo.setMyPhoto(url);
      ref.invalidate(myProfileProvider);
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not upload photo: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _bowling.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A display name is required.');
      return;
    }
    final newHandle = _handle.text.trim().toLowerCase();
    if (!_hasHandle && newHandle.isNotEmpty &&
        !RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(newHandle)) {
      setState(() =>
          _error = 'Handles are 3-30 letters, numbers or underscores.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(identityRepositoryProvider).updateMyProfile({
        'display_name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'bowling_style': _bowling.text.trim().isEmpty ? null : _bowling.text.trim(),
        'batting_style': _batting,
        'playing_role': _role,
        // MISS-5: a pre-handle account claims a handle here (write-once)
        if (!_hasHandle && newHandle.isNotEmpty) 'handle': newHandle,
      });
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('Profile saved')));
        context.pop();
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.code == '23505'
          ? 'That handle is taken - try another.'
          : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Edit profile',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                InitialsAvatar(name: _name.text, photoUrl: _photoUrl, radius: 44),
                TextButton.icon(
                  onPressed: _uploading ? null : _changePhoto,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Change photo'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}), // live initials preview (PROF-4)
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 12),
          // MISS-5: pre-handle accounts set their handle here; once set it is
          // your permanent address and shows read-only.
          if (_hasHandle)
            TextField(
              controller: _handle,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Handle',
                prefixText: '@',
                helperText: 'Handles are permanent',
              ),
            )
          else
            TextField(
              controller: _handle,
              decoration: const InputDecoration(
                labelText: 'Handle (optional, permanent once set)',
                prefixText: '@',
                helperText: '3-30 letters, numbers or underscores',
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'City'),
          ),
          const SizedBox(height: 20),
          Text('Batting', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in const {'right': 'Right-hand', 'left': 'Left-hand'}.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _batting == e.key,
                  onSelected: (_) => setState(() => _batting = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Role', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in const {
                'batter': 'Batter',
                'bowler': 'Bowler',
                'all_rounder': 'Allrounder',
                'keeper': 'Keeper',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _role == e.key,
                  onSelected: (_) => setState(() => _role = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bowling,
            decoration: const InputDecoration(
              labelText: 'Bowling style (e.g. Right-arm medium)',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
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
