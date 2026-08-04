import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../discover/data/discover_providers.dart';
import '../data/dm_realtime.dart';
import '../../discover/data/discover_repository.dart';
import '../../../core/ui/human_error.dart';
import '../../../core/platform/error_retry.dart';

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

class _DmThreadScreenState extends ConsumerState<DmThreadScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  final Set<String> _ids = {};
  void Function()? _detach;
  bool _loading = true;
  String? _loadError;
  bool _sending = false;

  String? get _me => ref.read(currentSessionProvider)?.user.id;

  @override
  void initState() {
    super.initState();
    // HIGH (whole-system review #2, finding 41): history loaded ONCE and every
    // message after it came from a broadcast callback, so a tunnel, a locked
    // phone or a dropped socket silently swallowed part of the conversation.
    // Nothing looked wrong - the thread reads as complete while the other
    // person is replying into a void. Three recoveries, the same ones the match
    // viewer got: on (re)subscribe, on return to the foreground, and
    // pull-to-refresh.
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS tears the socket down on a locked phone with no re-subscribe when
    // it wakes, so this is a distinct recovery, not a duplicate of the one
    // above.
    if (state == AppLifecycleState.resumed) {
      _resync();
      _refreshReceipts();
    }
  }

  /// Pull in whatever arrived while we were not listening. Asks only for what
  /// is newer than the newest message held - re-downloading the whole thread on
  /// every reconnect would trade finding 41 for finding 74.
  Future<void> _resync() async {
    if (!mounted || _loading) return;
    if (_loadError != null) return; // the retry button owns that path
    String? newest;
    for (final m in _messages) {
      if (m['pending'] == true) continue; // a local clock is not a cursor
      final at = m['created_at'] as String?;
      if (at != null && (newest == null || at.compareTo(newest) > 0)) {
        newest = at;
      }
    }
    try {
      final rows = await ref
          .read(discoverRepositoryProvider)
          .threadMessages(widget.threadId, after: newest);
      if (!mounted) return;
      final fresh = [
        for (final r in rows)
          if (!_ids.contains(r['id'] as String)) r,
      ];
      if (fresh.isEmpty) return;
      setState(() {
        for (final r in fresh) {
          _ids.add(r['id'] as String);
          _messages.add(r);
        }
      });
      _jump();
      // caught up while the thread is open, so they are read
      if (fresh.any((m) => m['sender_id'] != _me)) _markRead();
    } catch (_) {
      // a failed catch-up is not worth an error state over a healthy thread;
      // the next resume or pull-to-refresh tries again
    }
  }

  /// A throw here used to leave a PERMANENT spinner: no error, no retry, and
  /// _subscribe() never ran, so the thread was not even live once it recovered
  /// (penetration review 2026-07-07).
  Future<void> _init() async {
    try {
      // The MOST RECENT 200, then flipped back to oldest-first for display.
      // Loading the whole history meant a long-running conversation downloaded
      // every message it had ever contained just to show the last screenful
      // (review #2 finding 74).
      //
      // KNOWN GAP: this caps the thread rather than paginating it, so messages
      // older than the most recent 200 are not reachable in the UI. That is a
      // deliberate trade for now - unbounded download on a phone is worse - but
      // it is a cap, not a solution, and back-pagination is still owed.
      final rows = await ref
          .read(discoverRepositoryProvider)
          .threadMessages(widget.threadId);
      for (final r in rows) {
        _ids.add(r['id'] as String);
        _messages.add(r);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = humanError(
            e,
            fallback: 'Could not load this conversation.',
          );
        });
      }
      return; // do not subscribe/mark-read against a failed load
    }
    _subscribe();
    _jump();
    _markRead();
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadError = null;
      _messages.clear();
      _ids.clear();
    });
    _init();
  }

  /// The sent / delivered / seen ticks on MY OWN messages.
  ///
  /// The stamps live on rows already on screen, so a re-sync keyed on
  /// created_at would never see them change. The server sends one RECEIPT
  /// broadcast per statement on the same `dm:<thread>` topic; this re-reads the
  /// stamps (not the bodies) and merges them in place.
  Future<void> _refreshReceipts() async {
    if (!mounted) return;
    try {
      final rows = await ref
          .read(discoverRepositoryProvider)
          .myReceipts(widget.threadId);
      if (!mounted || rows.isEmpty) return;
      final byId = {for (final r in rows) r['id'] as String: r};
      var changed = false;
      for (final m in _messages) {
        final r = byId[m['id']];
        if (r == null) continue;
        if (m['delivered_at'] != r['delivered_at'] ||
            m['read_at'] != r['read_at']) {
          m['delivered_at'] = r['delivered_at'];
          m['read_at'] = r['read_at'];
          changed = true;
        }
      }
      if (changed) setState(() {});
    } catch (_) {
      // a tick that failed to refresh is not worth interrupting a conversation
    }
  }

  /// Tells the SENDER their message reached this device - the second tick.
  /// markThreadRead implies it, so this only matters for the moment between
  /// arriving and being looked at.
  Future<void> _markDelivered() async {
    try {
      await ref
          .read(discoverRepositoryProvider)
          .markThreadDelivered(widget.threadId);
    } catch (_) {
      /* non-fatal */
    }
  }

  /// DM-4: opening the thread clears the unread state (secured RPC) and
  /// refreshes the inbox badge.
  Future<void> _markRead() async {
    try {
      await ref
          .read(discoverRepositoryProvider)
          .markThreadRead(widget.threadId);
      ref.invalidate(dmInboxProvider);
    } catch (_) {
      /* non-fatal */
    }
  }

  void _subscribe() {
    // ONE shared channel per topic (DmRealtime). This screen used to open its
    // own channel on 'dm:<id>' while the inbox already had one on the same
    // topic - two joins on one topic, which killed live delivery in the very
    // conversation the user was reading (penetration review 2026-07-07).
    _detach = ref
        .read(dmRealtimeProvider)
        .listen(
          widget.threadId,
          (record) {
            if (!mounted) return;
            final id = record['id'] as String?;
            if (id == null || _ids.contains(id)) return;
            _ids.add(id);
            setState(() => _messages.add(record));
            _jump();
            // an incoming message while the thread is open is instantly read, and
            // read implies delivered, so their ticks move in one step
            if (record['sender_id'] != _me) {
              _markDelivered();
              _markRead();
            }
          },
          onSubscribed: () {
            _resync();
            _refreshReceipts();
          },
          onReceipt: _refreshReceipts,
        );
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              raw.contains('row-level security')
                  ? 'You cannot message this user.'
                  : 'Message not sent - check your connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// sent / delivered / seen, in the order a message actually travels:
  ///
  ///   clock      still being written to the server
  ///   one tick   the server has it
  ///   two ticks  their app has it (delivered_at)
  ///   two blue   they opened the thread (read_at)
  ///
  /// The distinction a captain chasing a fixture cares about is between "it
  /// never reached them" and "they have read it and not replied".
  static Widget _tick(Map<String, dynamic> m, {required bool pending}) {
    if (pending) {
      return const Icon(Icons.schedule, size: 12, color: Colors.white70);
    }
    final seen = m['read_at'] != null;
    final delivered = seen || m['delivered_at'] != null;
    return Icon(
      delivered ? Icons.done_all : Icons.done,
      size: 13,
      color: seen ? const Color(0xFF8AD8FF) : Colors.white70,
    );
  }

  /// DM-6: a compact bubble time, day-aware ("14:05" today, "Mon 14:05" else).
  static String _timeLabel(dynamic createdAt) {
    final dt = DateTime.tryParse(createdAt?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:'
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
    WidgetsBinding.instance.removeObserver(this);
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
          'be able to message them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
      messenger?.showSnackBar(
        SnackBar(content: Text(humanError(e, fallback: 'Could not block.'))),
      );
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
            child: _loadError != null
                ? ErrorRetry(message: _loadError!, onRetry: _retryLoad)
                : _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : RefreshIndicator.adaptive(
                    onRefresh: () async {
                      await _resync();
                      await _refreshReceipts();
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final mine = m['sender_id'] == _me;
                        final pending = m['pending'] == true;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
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
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _timeLabel(m['created_at']),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: mine
                                            ? Colors.white70
                                            : Colors.black45,
                                      ),
                                    ),
                                    // Receipts belong on YOUR OWN messages only
                                    if (mine) ...[
                                      const SizedBox(width: 4),
                                      _tick(m, pending: pending),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
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
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
