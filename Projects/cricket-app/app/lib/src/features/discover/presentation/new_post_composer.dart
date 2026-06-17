import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../identity/data/identity_providers.dart';
import '../data/discover_models.dart';
import '../data/discover_providers.dart';
import '../data/discover_repository.dart';
import 'flair_chip.dart';

class NewPostComposer extends ConsumerStatefulWidget {
  const NewPostComposer({super.key});

  @override
  ConsumerState<NewPostComposer> createState() => _NewPostComposerState();
}

class _NewPostComposerState extends ConsumerState<NewPostComposer> {
  String _mode = 'player_seeking_team';
  String? _flair; // required
  String? _teamId; // required for team_seeking_*
  final _details = TextEditingController();
  final _place = TextEditingController();
  final _link = TextEditingController();
  final List<String> _imageUrls = [];
  bool _busy = false;
  bool _uploading = false;
  String? _error;

  bool get _needsTeam => _mode != 'player_seeking_team';

  @override
  void dispose() {
    _details.dispose();
    _place.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final picked = await ImagePicker().pickMultiImage(limit: 6, imageQuality: 80);
    if (picked.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final repo = ref.read(discoverRepositoryProvider);
      for (final x in picked) {
        if (_imageUrls.length >= 6) break;
        final bytes = await x.readAsBytes();
        final ext = x.name.contains('.') ? x.name.split('.').last : 'jpg';
        final url = await repo.uploadPostImage(bytes, ext);
        if (mounted) setState(() => _imageUrls.add(url));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _post() async {
    if (_flair == null) {
      setState(() => _error = 'Pick a flair.');
      return;
    }
    if (_needsTeam && _teamId == null) {
      setState(() => _error = 'Pick which team this post is for.');
      return;
    }
    final anchor = ref.read(anchorProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(discoverRepositoryProvider).createPost(
            mode: _mode,
            flair: _flair!,
            lat: anchor.lat,
            lng: anchor.lng,
            teamId: _needsTeam ? _teamId : null,
            description: _details.text.trim(),
            placeLabel: _place.text.trim(),
            imageUrls: _imageUrls,
            linkUrl: _link.text.trim(),
          );
      ref.invalidate(discoverFeedProvider);
      ref.invalidate(myPostsProvider);
      if (mounted) context.pop();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myTeams = ref.watch(myTeamsProvider);
    return AdaptiveScaffold(
      title: 'New post',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text("I'm looking for", style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in LfLabels.modes.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _mode == e.key,
                  onSelected: (_) => setState(() => _mode = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Flair', style: Theme.of(context).textTheme.labelLarge),
              const Text(' (required)', style: TextStyle(color: Colors.red)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final key in LfLabels.flairs.keys)
                GestureDetector(
                  onTap: () => setState(() => _flair = key),
                  child: Opacity(
                    opacity: _flair == null || _flair == key ? 1 : 0.4,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        FlairChip(key),
                        if (_flair == key)
                          const Positioned(
                            right: 2,
                            child: Icon(Icons.check, size: 14),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (_needsTeam) ...[
            const SizedBox(height: 16),
            Text('Team', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            myTeams.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Could not load teams.\n$e'),
              data: (rows) {
                final admin = [
                  for (final r in rows)
                    if (r['role'] == 'captain' || r['role'] == 'admin')
                      r['teams'] as Map<String, dynamic>,
                ];
                if (admin.isEmpty) {
                  return const Text('You must captain/admin a team to post this.');
                }
                return DropdownButton<String>(
                  isExpanded: true,
                  value: _teamId,
                  hint: const Text('Choose a team'),
                  items: [
                    for (final t in admin)
                      DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setState(() => _teamId = v),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _place,
            decoration: const InputDecoration(labelText: 'Where (ground / area)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Details'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Link (optional)',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: (_uploading || _imageUrls.length >= 6)
                    ? null
                    : _addPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('Add photos (${_imageUrls.length}/6)'),
              ),
              if (_uploading) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ],
            ],
          ),
          if (_imageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _imageUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _imageUrls[i],
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _imageUrls.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _post,
            child: const Text('Post'),
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
