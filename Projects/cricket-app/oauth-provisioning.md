---
type: reference
date: 2026-06-23
project: cricket-app
tags: [cricket-app, auth, oauth, provisioning]
---

# Google / Apple sign-in - provisioning checklist

## Concrete values (collected 2026-06-27)
- App identifiers: Android package `dev.pitch.pitch_app`; iOS bundle `dev.pitch.pitchApp`.
- Debug-keystore SHA-1 (for test builds; add the Play App Signing SHA-1 at store time): `93:8A:C0:0B:ED:94:13:CA:EB:2A:2E:CF:64:1D:05:A1:F8:23:1E:56`.
- Hosted Supabase project ref `ocejkqihgiinonpyafhl` -> URL `https://ocejkqihgiinonpyafhl.supabase.co`. anon + service_role keys provided by the user (in their protected env; do NOT echo). Free tier.
- Google Cloud project `cric-app-500700`. WEB OAuth client (for Supabase, already configured in Supabase Auth->Providers->Google): client_id `648807538669-glnujekrp915tlomvv6n88fdmk970vgn.apps.googleusercontent.com` (web client_secret is in Supabase's provider config; not used by the app).
- DECISION: Google sign-in only for v1; Apple deferred.
- ANDROID OAuth client: CREATED 2026-06-27. client_id `648807538669-nnftd275c6gcqksmv1pneqgbrk0u0teb.apps.googleusercontent.com` (package `dev.pitch.pitch_app` + debug SHA-1 above). This id is NOT used in app code and NOT added to the Supabase Client IDs field; google_sign_in trusts the app via package+SHA at runtime + uses the WEB id as serverClientId (so the id_token aud = web id). It just needs to EXIST, which it now does.
- SUPABASE GOOGLE PROVIDER: CONFIGURED 2026-06-27 (Enable ON; Client IDs = web id only; Client Secret per dashboard; Skip nonce checks ON).
- RELEASE KEYSTORE (created 2026-06-27 for the friend-sharing release APK): file `~/pitch-release-keystore.jks` (PKCS12, alias `pitch`, validity 10000d, OUTSIDE the repo, 600 perms); passwords in `app/android/key.properties` (GITIGNORED - back BOTH up; losing them = can't update the app / Play upload key, though Play App Signing makes the upload key resettable). **Release SHA-1 = `43:1A:49:F8:E3:83:4E:09:31:8D:2F:CD:64:54:00:55:9D:05:52:4F`.** build.gradle.kts now signs release with this key when key.properties exists (else falls back to debug). RELEASE Android OAuth client CREATED 2026-06-27: client_id `648807538669-ligdf8rbjt9joauhd9dfflpm8orbpt4h.apps.googleusercontent.com` (package `dev.pitch.pitch_app` + the RELEASE SHA-1 below). Like the debug Android client, this id is used NOWHERE in code and is NOT added to Supabase Client IDs - Android matches the app by package+SHA-1 at runtime; the app uses the WEB id as serverClientId so the token aud = web id. It just needs to exist (it now does). Debug SHA-1 client still covers `flutter run` + debug APKs. Reminder: ALL Google client ids so far -> debug Android (no id needed in code), release Android `...ligdf8...` (no id in code), web `...glnujekrp915...` (in code as serverClientId + Supabase Client IDs). Only the future iOS client id goes in code (GOOGLE_IOS_CLIENT_ID + Info.plist reversed id).
- STILL NEEDED: (a) an iOS-type Google OAuth client (bundle `dev.pitch.pitchApp`) -> need its client id + reversed-client-id for Info.plist; (b) to HOST/migrate the backend, the DB password OR a Supabase access token (anon/service_role can't run DDL).
- BUILD WIRING (when ready): pass `--dart-define SUPABASE_URL=https://ocejkqihgiinonpyafhl.supabase.co --dart-define SUPABASE_PUBLISHABLE_KEY=<anon> --dart-define GOOGLE_WEB_CLIENT_ID=648807538669-...apps.googleusercontent.com --dart-define GOOGLE_IOS_CLIENT_ID=<ios>` (env.dart reads these). Note: env.dart `googleConfigured` currently requires BOTH web+ios ids; make platform-aware if testing Android-only Google sign-in before the iOS client exists.



The OAuth **code is wired** (`app/lib/src/features/auth/data/oauth_sign_in.dart`,
buttons in `sign_in_screen.dart`). It uses the native ID-token flow Supabase
recommends for mobile: Google native on iOS+Android, Apple native on iOS
(Android falls back to the Supabase browser flow; the Apple button is gated to
iOS for v1). Until the items below are provisioned, the Google button reports
"not configured" and the buttons surface a friendly error - nothing crashes.
The local `kDebugMode` email/password shim (`dev@pitch.local` / `password123`)
is untouched and stays the working local path.

Verified against current docs via workflow wf_039c5889-a39 (2026). Packages:
`google_sign_in ^7.2.0`, `sign_in_with_apple ^8.1.0`, `crypto ^3.0.7`,
`supabase_flutter ^2.15.0`.

## What only YOU can do (accounts/credentials)

### A. Hosted Supabase (prerequisite)
- Create a hosted Supabase project. Note the **project ref** and the callback
  URL `https://<project-ref>.supabase.co/auth/v1/callback`.
- `supabase link` + `supabase db push` to apply the 60 migrations (seed.sql is
  local-only and not pushed).
- Build the app against it: `--dart-define SUPABASE_URL=https://<ref>.supabase.co --dart-define SUPABASE_PUBLISHABLE_KEY=<publishable key>`.

### B. Google (both platforms)
1. Google Cloud project + OAuth consent screen.
2. **Web** OAuth client - add redirect URI `https://<ref>.supabase.co/auth/v1/callback`. Copy its **Client ID** (= `GOOGLE_WEB_CLIENT_ID` / serverClientId) + secret.
3. **iOS** OAuth client, Bundle ID `dev.pitch.pitchApp`. Copy its **Client ID** (= `GOOGLE_IOS_CLIENT_ID`) and note its **reversed** client id (`com.googleusercontent.apps.NNNN-xxxx`).
4. Android signing SHA-1(s): `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android` (debug), plus release + Play App Signing SHA-1.
5. **Android** OAuth client for each SHA-1, package `dev.pitch.pitch_app`.
6. Supabase Dashboard > Auth > Providers > **Google**: enable; in **Client IDs** put ONLY the **Web** id (and, once it exists, the **iOS** id), comma-separated, web FIRST: `<web>[,<ios>]`. **Do NOT add the Android client id(s) to this field** - the Android client never appears as the token's `aud`; the app passes the WEB id as `serverClientId`, so Google mints the id_token with `aud` = web id on BOTH platforms, and that is what Supabase validates against this list. The Android client only needs to EXIST in Google Cloud (package + SHA-1) to authorize the app to Google. Leave **Client Secret** EMPTY (the native idToken flow never uses it; paste the web secret only if the dashboard refuses to Save). Enable **Skip nonce check** (google_sign_in v7 sends no nonce; required so native iOS tokens validate - safe to turn on now). **Callback URL** is read-only and unused by the native flow. (Verified via workflow wf_df81a5c5-7ec, 2026-06-27.)

### C. Apple (iOS-only, minimal v1)
1. Apple Developer Program ($99/yr); note the 10-char Team ID.
2. Identifiers > App ID for `dev.pitch.pitchApp` > enable **Sign in with Apple**.
3. Supabase Dashboard > Auth > Providers > **Apple**: enable; put `dev.pitch.pitchApp` in **Client IDs**. (For iOS-native only, NO Services ID / .p8 key / generated secret is needed.)
4. *(Only if you later want Apple on Android/web)* additionally create a Services ID + Sign-in key (.p8) + generate the Supabase secret (a JWT that expires ~6 months - set a reminder), and add `io.supabase.pitch://login-callback` to Supabase > Auth > URL Configuration > Redirect URLs + the platform config in step D3/D4.

### D. Hand the developer these values
- `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` (for `--dart-define`), and the **reversed iOS client id** (for Info.plist below).

## Platform config to add (a developer applies these, using YOUR values)

1. **iOS native Google** - `ios/Runner/Info.plist`, add inside the top `<dict>`:
   ```xml
   <key>CFBundleURLTypes</key>
   <array><dict>
     <key>CFBundleURLSchemes</key>
     <array><string>com.googleusercontent.apps.YOUR-REVERSED-IOS-CLIENT-ID</string></array>
   </dict></array>
   ```
   (No `GIDClientID` / GoogleService-Info.plist needed - the client id is passed in Dart.)
2. **iOS native Apple** - in Xcode, Runner target > Signing & Capabilities > + **Sign in with Apple** (writes `Runner.entitlements` with `com.apple.developer.applesignin`). No URL scheme/associated-domain needed.
3. **Android** - no manifest change for native Google. *(Only for the Apple-on-Android browser fallback)* add inside `<activity android:name=".MainActivity">`:
   ```xml
   <intent-filter>
     <action android:name="android.intent.action.VIEW"/>
     <category android:name="android.intent.category.DEFAULT"/>
     <category android:name="android.intent.category.BROWSABLE"/>
     <data android:scheme="io.supabase.pitch" android:host="login-callback"/>
   </intent-filter>
   ```
4. Keep the scheme identical everywhere (`io.supabase.pitch://login-callback`) if you enable the Android fallback.

## Known caveats (from the verification)
- The Supabase Dart **reference** page for `signInWithIdToken` still shows the old `google_sign_in` v6 API; this code uses the correct v7 token split (idToken from `.authentication`, accessToken from `.authorizationClient`).
- `signInWithIdToken` upgrades the boot **anonymous** session to a permanent account - the user id changes; anon-keyed local state is not auto-migrated (out of scope for wiring; revisit if drafts/posts are written pre-login).
- Apple returns the user's name only on the **first** authorization - captured via `updateUser({full_name})` on first sign-in.
- Android Google with Play App Signing: register the Play re-signing SHA-1 too, or production sign-in fails silently.
