import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../data/oauth_sign_in.dart';
import '../../../core/ui/human_error.dart';

/// Sign-in. The Google/Apple buttons call the native OAuth flow
/// (oAuthServiceProvider); they surface a friendly error until the OAuth client
/// IDs are configured (the credential-boundary step). In debug builds an
/// email/password shim signs in against the local stack so the app is usable now.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  // Prefilled ONLY in debug. These are real credentials for a real account on
  // the hosted project, and they were shipping inside the release binary -
  // anyone with the APK could sign in as that identity against production
  // (penetration review 2026-07-07). Release builds start empty.
  final _email =
      TextEditingController(text: kDebugMode ? 'dev@pitch.local' : '');
  final _password =
      TextEditingController(text: kDebugMode ? 'password123' : '');
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
    } catch (e) {
      // OAuth plugins throw their own exception types (cancellation, etc.).
      setState(() => _message = humanError(e, fallback: 'Sign-in failed.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        () => ref
                            .read(supabaseClientProvider)
                            .auth
                            .signInWithPassword(
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
                        () => ref.read(supabaseClientProvider).auth.signUp(
                          email: _email.text.trim(),
                          password: _password.text,
                        ),
                      ),
                child: const Text('Create test account (dev)'),
              ),
              const Divider(height: 32),
            ],
            // SupabaseEnv.googleConfigured has existed since the OAuth wiring
            // and was never consulted, so this button was always shown - and on
            // iOS without GOOGLE_IOS_CLIENT_ID (plus its reversed-client-id URL
            // scheme in Info.plist) it opens a flow that cannot come back. An
            // offer the app cannot honour is worse than no offer: the user
            // assumes their account is broken (whole-system review #2).
            if (SupabaseEnv.googleConfigured)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref.read(oAuthServiceProvider).nativeGoogleSignIn(),
                      ),
                child: const Text('Continue with Google'),
              ),
            // Sign in with Apple is native on iOS; gated there for v1 (Android
            // users sign in with Google).
            if (defaultTargetPlatform == TargetPlatform.iOS) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref.read(oAuthServiceProvider).appleSignIn(),
                      ),
                child: const Text('Continue with Apple'),
              ),
            ],
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
