import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../discover/data/discover_repository.dart';

/// A 1:1 DM thread. Loads history once, then subscribes to the private
/// `dm:<threadId>` broadcast channel and appends new messages live.
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
  RealtimeChannel? _channel;
  bool _loading = true;

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
  }

  void _subscribe() {
    // Private channel needs a JWT on the socket for the participant-scoped
    // receive policy.
    _c.realtime.setAuth(_c.auth.currentSession?.accessToken);
    final channel = _c.channel(
      'dm:${widget.threadId}',
      opts: const RealtimeChannelConfig(private: true),
    );
    channel
        .onBroadcast(
          event: 'INSERT',
          callback: (payload) {
            final record =
                (payload['payload'] as Map?)?['record'] as Map<String, dynamic>?;
            if (record == null) return;
            final id = record['id'] as String?;
            if (id == null || _ids.contains(id)) return;
            _ids.add(id);
            setState(() => _messages.add(record));
            _jump();
          },
        )
        .subscribe();
    _channel = channel;
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    _input.clear();
    await ref.read(discoverRepositoryProvider).sendDm(widget.threadId, body);
    // the broadcast INSERT echoes back and appends for everyone (incl. us).
  }

  @override
  void dispose() {
    if (_channel != null) _c.removeChannel(_channel!);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Chat',
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
                          child: Text(
                            m['body'] as String,
                            style: TextStyle(
                              color: mine ? Colors.white : Colors.black87,
                            ),
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
                  IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
