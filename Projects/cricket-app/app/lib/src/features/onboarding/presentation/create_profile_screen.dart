import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/supabase/supabase_providers.dart';

/// First-run gate: a real (non-anonymous) user with no profile row lands here.
/// Collects the essentials (name + a unique handle, plus optional city/style/
/// role), upserts the row, and invalidates [myProfileProvider], which refreshes
/// the router and moves them into the shell.
class CreateProfileScreen extends ConsumerStatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  ConsumerState<CreateProfileScreen> createState() =>
      _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  static final _handleRe = RegExp(r'^[A-Za-z0-9_]{3,30}$');

  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _city = TextEditingController();
  String? _batting; // 'right' | 'left'
  String? _role; // batter | bowler | all_rounder | keeper

  bool _busy = false;
  String? _error;

  // Live handle availability.
  bool _checkingHandle = false;
  bool? _handleFree; // null = unknown / not yet valid
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // AUTH-5: prefill the display name from the OAuth identity so first-run is
    // one tap for most users. Best-effort: never block first render on it.
    try {
      final md = ref
              .read(supabaseClientProvider)
              .auth
              .currentSession
              ?.user
              .userMetadata ??
          const <String, dynamic>{};
      final full = (md['full_name'] ?? md['name']) as String?;
      if (full != null && full.trim().isNotEmpty) _name.text = full.trim();
    } catch (_) {
      // no client/session available (e.g. widget tests) - skip prefill.
    }
    _handle.addListener(_onHandleChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _handle.removeListener(_onHandleChanged);
    _name.dispose();
    _handle.dispose();
    _city.dispose();
    super.dispose();
  }

  void _onHandleChanged() {
    _debounce?.cancel();
    final h = _handle.text.trim();
    setState(() => _handleFree = null);
    if (!_handleRe.hasMatch(h)) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _checkingHandle = true);
      try {
        final free = await ref
            .read(supabaseClientProvider)
            .rpc('handle_available', params: {'_handle': h});
        if (mounted && _handle.text.trim() == h) {
          setState(() => _handleFree = free as bool);
        }
      } catch (_) {
        // Final uniqueness is enforced on save; ignore transient check errors.
      } finally {
        if (mounted) setState(() => _checkingHandle = false);
      }
    });
  }

  bool get _handleValid => _handleRe.hasMatch(_handle.text.trim());
  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _handleValid &&
      _handleFree == true &&
      !_busy;

  Future<void> _save() async {
    final client = ref.read(supabaseClientProvider);
    final session = client.auth.currentSession;
    if (session == null || !_canSave) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // AUTH-4: upsert (not a bare insert) so a re-submit or a pre-existing row
      // doesn't crash with a raw 23505.
      await client.from('profiles').upsert({
        'id': session.user.id,
        'display_name': _name.text.trim(),
        'handle': _handle.text.trim(),
        if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        if (_batting != null) 'batting_style': _batting,
        if (_role != null) 'playing_role': _role,
      });
      ref.invalidate(myProfileProvider);
    } on PostgrestException catch (e) {
      setState(() => _error = e.code == '23505'
          ? 'That handle is already taken - pick another.'
          : (e.message.isNotEmpty
              ? e.message
              : 'Could not save your profile. Please try again.'));
    } catch (_) {
      setState(() => _error = 'Could not save your profile. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget? _handleSuffix() {
    if (_checkingHandle) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (_handle.text.trim().isEmpty) return null;
    if (!_handleValid || _handleFree == false) {
      return const Icon(Icons.error_outline, color: Colors.redAccent);
    }
    if (_handleFree == true) {
      return const Icon(Icons.check_circle_outline, color: Color(0xFF0F6E56));
    }
    return null;
  }

  String? _handleHelper() {
    final h = _handle.text.trim();
    if (h.isEmpty) return '3-30 letters, numbers or underscores';
    if (!_handleValid) return 'Use 3-30 letters, numbers or underscores';
    if (_handleFree == false) return 'That handle is taken';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Create profile',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _handle,
            autocorrect: false,
            maxLength: 30,
            decoration: InputDecoration(
              labelText: 'Handle',
              prefixText: '@',
              suffixIcon: _handleSuffix(),
              helperText: _handleHelper(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'City (optional)'),
          ),
          const SizedBox(height: 20),
          Text('Batting', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'right', label: Text('Right')),
              ButtonSegment(value: 'left', label: Text('Left')),
            ],
            selected: _batting == null ? <String>{} : {_batting!},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) =>
                setState(() => _batting = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration:
                const InputDecoration(labelText: 'Playing role (optional)'),
            items: const [
              DropdownMenuItem(value: 'batter', child: Text('Batter')),
              DropdownMenuItem(value: 'bowler', child: Text('Bowler')),
              DropdownMenuItem(value: 'all_rounder', child: Text('All-rounder')),
              DropdownMenuItem(value: 'keeper', child: Text('Wicket-keeper')),
            ],
            onChanged: (v) => setState(() => _role = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canSave ? _save : null,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }
}
