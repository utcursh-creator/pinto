import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../discover/data/discover_providers.dart';
import '../data/dm_realtime.dart';
import '../../discover/data/discover_repository.dart';

/// A 1:1 DM thread. Loads history once, then subscribes to the private
/// `dm:<threadId>` broadcast channel and appends new messages live. The header
/// names the other participant (DM-1); opening marks their messages read
/// (DM-4); sends are optimistic and survive failure (DM-3); bubbles carry
/// timestamps (DM-6).
class DmThreadScreen extends ConsumerStatefulWidget {
  const DmThreadScreen({required this.threadId, super.key});

  final String threadId;

  @override
  ConsumerState<DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends ConsumerState<DmThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  final Set<String> _ids = {};
  void Function()? _detach;
  bool _loading = true;
  bool _sending = false;

  SupabaseClient get _c => ref.read(supabaseClientProvider);
  String? get _me => _c.auth.currentSession?.user.id;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final rows = await _c
        .from('dm_messages')
        .select('id, sender_id, body, created_at')
        .eq('thread_id', widget.threadId)
        .order('created_at');
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      _ids.add(r['id'] as String);
      _messages.add(r);
    }
    if (mounted) setState(() => _loading = false);
    _subscribe();
    _jump();
    _markRead();
  }

  /// DM-4: opening the thread clears the unread state (secured RPC) and
  /// refreshes the inbox badge.
  Future<void> _markRead() async {
    try {
      await ref.read(discoverRepositoryProvider).markThreadRead(widget.threadId);
      ref.invalidate(dmInboxProvider);
    } catch (_) {/* non-fatal */}
  }

  void _subscribe() {
    // ONE shared channel per topic (DmRealtime). This screen used to open its
    // own channel on 'dm:<id>' while the inbox already had one on the same
    // topic - two joins on one topic, which killed live delivery in the very
    // conversation the user was reading (penetration review 2026-07-07).
    _detach = ref.read(dmRealtimeProvider).listen(widget.threadId, (record) {
      if (!mounted) return;
      final id = record['id'] as String?;
      if (id == null || _ids.contains(id)) return;
      _ids.add(id);
      setState(() => _messages.add(record));
      _jump();
      // an incoming message while the thread is open is instantly read
      if (record['sender_id'] != _me) _markRead();
    });
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// DM-3: optimistic append; the input is only cleared once the insert
  /// succeeds, and on failure the text is restored with an error.
  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = <String, dynamic>{
      'id': tempId,
      'sender_id': _me,
      'body': body,
      'created_at': DateTime.now().toIso8601String(),
      'pending': true,
    };
    setState(() {
      _messages.add(optimistic);
      _input.clear();
    });
    _jump();
    try {
      final row = await ref
          .read(discoverRepositoryProvider)
          .sendDm(widget.threadId, body);
      // DM-3: the insert returns the real row - swap the placeholder for it
      // directly. The `_ids` guard dedupes the broadcast echo when it arrives;
      // if the echo is dropped the message still stands.
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempId);
          final id = row['id'] as String?;
          if (id != null && !_ids.contains(id)) {
            _ids.add(id);
            _messages.add(row);
          }
        });
        _jump();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempId);
          _input.text = body; // restore so nothing is lost
        });
        final raw = '$e';
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(raw.contains('row-level security')
                ? 'You cannot message this user.'
                : 'Message not sent - check your connection.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// DM-6: a compact bubble time, day-aware ("14:05" today, "Mon 14:05" else).
  static String _timeLabel(dynamic createdAt) {
    final dt = DateTime.tryParse(createdAt?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return hm;
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[dt.weekday - 1]} $hm';
  }

  @override
  void dispose() {
    // no ref.read() here: Riverpod throws StateError once the element is gone,
    // which previously leaked the channel AND the controllers below it.
    _detach?.call();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// SEC-3: confirmed block - closes the DM channel both ways, then leaves.
  Future<void> _blockUser(String userId, String name) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
            'They will no longer be able to message you, and you will not '
            'be able to message them.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(discoverRepositoryProvider).blockUser(userId);
      ref.invalidate(dmInboxProvider);
      messenger?.showSnackBar(SnackBar(content: Text('$name blocked')));
      if (mounted && context.canPop()) context.pop();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not block: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // DM-1: the header names the person, not "Chat".
    final other = ref.watch(threadOtherProvider(widget.threadId)).value;
    return AdaptiveScaffold(
      title: (other?['display_name'] as String?) ?? 'Chat',
      actions: [
        // SEC-3 (final audit): the block backend existed with zero call sites.
        if (other?['id'] != null)
          PopupMenuButton<String>(
            onSelected: (_) => _blockUser(
              other!['id'] as String,
              (other['display_name'] as String?) ?? 'this user',
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'block', child: Text('Block user')),
            ],
          ),
      ],
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final mine = m['sender_id'] == _me;
                      final pending = m['pending'] == true;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFF0F6E56)
                                : const Color(0xFFEDEDED),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                m['body'] as String,
                                style: TextStyle(
                                  color: mine ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pending ? 'sending...' : _timeLabel(m['created_at']),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: mine ? Colors.white70 : Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _sending ? null : _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
