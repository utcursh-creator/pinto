import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Google/Apple sign-in surface. Abstract so widget tests can supply a fake
/// without a live SupabaseClient.
abstract interface class OAuthService {
  Future<void> nativeGoogleSignIn();
  Future<void> appleSignIn();
}

/// Real implementation via Supabase. On iOS+Android, Google uses the native OS
/// dialog (google_sign_in v7) and exchanges the provider ID token via
/// `signInWithIdToken`; Apple is native on iOS and falls back to the Supabase
/// browser flow on Android (no native Apple dialog there). The local debug
/// email/password shim is unaffected. Because the app boots an anonymous
/// session, a successful sign-in upgrades it to a permanent account.
class SupabaseOAuthService implements OAuthService {
  SupabaseOAuthService(this._client);

  final SupabaseClient _client;
  bool _googleInitialized = false;

  /// Native Google sign-in (iOS + Android).
  @override
  Future<void> nativeGoogleSignIn() async {
    if (!SupabaseEnv.googleConfigured) {
      throw const AuthException(
        'Google sign-in is not configured yet. Add the Google client IDs '
        '(see oauth-provisioning.md).',
      );
    }
    final gsi = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await gsi.initialize(
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? SupabaseEnv.googleIosClientId
            : null,
        serverClientId: SupabaseEnv.googleWebClientId,
      );
      _googleInitialized = true;
    }

    // attemptLightweightAuthentication() returns null for first-time users;
    // authenticate() then shows the interactive dialog (throws if cancelled).
    final user = await gsi.attemptLightweightAuthentication() ??
        await gsi.authenticate();
    final idToken = user.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token.');
    }
    // v7 splits authentication (idToken) from authorization (accessToken).
    const scopes = ['email', 'profile'];
    final authz =
        await user.authorizationClient.authorizationForScopes(scopes) ??
            await user.authorizationClient.authorizeScopes(scopes);

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authz.accessToken,
    );
  }

  /// Apple sign-in: native on iOS, Supabase browser flow on Android.
  @override
  Future<void> appleSignIn() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _nativeAppleSignIn();
    }
    // Android has no native Apple dialog -> Supabase browser/redirect flow.
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'io.supabase.pitch://login-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> _nativeAppleSignIn() async {
    // Apple wants the SHA256-hashed nonce; Supabase verifies against the raw one.
    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final cred = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final idToken = cred.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple did not return an identity token.');
    }
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple returns the name only on the first authorization - persist it.
    final given = cred.givenName;
    if (given != null && given.isNotEmpty) {
      final full = '$given ${cred.familyName ?? ''}'.trim();
      await _client.auth.updateUser(UserAttributes(data: {'full_name': full}));
    }
  }
}

final oAuthServiceProvider = Provider<OAuthService>(
  (ref) => SupabaseOAuthService(ref.read(supabaseClientProvider)),
);
