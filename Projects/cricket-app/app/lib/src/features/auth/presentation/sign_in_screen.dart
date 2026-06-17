import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Sign-in. The real Google/Apple buttons are stubbed (wired in a later slice
/// once OAuth providers are configured). In debug builds an email/password
/// shim signs in against the local stack so the app is usable now.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController(text: 'dev@pitch.local');
  final _password = TextEditingController(text: 'password123');
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.read(supabaseClientProvider);
    return AdaptiveScaffold(
      title: 'Sign in',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            if (kDebugMode) ...[
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => client.auth.signInWithPassword(
                          email: _email.text.trim(),
                          password: _password.text,
                        ),
                      ),
                child: const Text('Sign in (dev)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => client.auth.signUp(
                          email: _email.text.trim(),
                          password: _password.text,
                        ),
                      ),
                child: const Text('Create test account (dev)'),
              ),
              const Divider(height: 32),
            ],
            OutlinedButton(
              onPressed: () => setState(
                () => _message = 'Google sign-in is wired in a later slice',
              ),
              child: const Text('Continue with Google'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(
                () => _message = 'Apple sign-in is wired in a later slice',
              ),
              child: const Text('Continue with Apple'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }
}
