/// Build-time configuration. Override with `--dart-define SUPABASE_URL=...`
/// and `--dart-define SUPABASE_PUBLISHABLE_KEY=...`. The defaults target the
/// LOCAL `supabase start` stack (the well-known local key is not a secret).
class SupabaseEnv {
  const SupabaseEnv._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  /// The local stack's publishable key (from `supabase status`). supabase_flutter
  /// 2.15 deprecated the legacy `anonKey` init param in favor of this.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );
}
