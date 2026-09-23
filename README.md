# Gujarati Dialect Dataset Curator

A Flutter application built with Supabase for crowdsourcing and curating high-quality audio recordings across various Gujarati dialects.

## Features
- **Strict Audio Validation**: Records in 16-bit 16kHz Mono WAV, parsing binary headers client-side before uploading.
- **Dialect Filtering**: Users onboard with a primary dialect, which cascades into the recording UI and prompt submissions.
- **User Prompts**: Volunteers can submit custom sentences, which are validated for Gujarati script density (>= 50%).
- **Private Audio Bucket**: Audio blobs are private; users stream their own uploads via 1-hour signed URLs. Admins can view and stream all uploads.

## Setup Instructions

### 1. Database & Storage (Supabase)
1. Create a new Supabase project.
2. Run the `supabase_setup.sql` script in the Supabase SQL Editor. This will provision all tables, configure RLS, create the `audio-clips` storage bucket (set to PRIVATE), and insert necessary database triggers.
3. For local development or quick testing, disable "Confirm email" in the Supabase Auth Settings. Otherwise, users will need a valid email to sign in.
4. To grant yourself admin access, sign up in the app, then run the following in the SQL Editor:
   ```sql
   UPDATE profiles SET is_admin = true WHERE id = 'YOUR_UUID_HERE';
   ```

### 2. Flutter Environment
You must inject the Supabase credentials at compile-time using `--dart-define`. **Do not hardcode keys in source files.**

To run the app locally:
```bash
flutter run --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

### 3. Permissions
Ensure your testing device/emulator has microphone permissions granted.
- **Android**: `<uses-permission android:name="android.permission.RECORD_AUDIO" />` is required in the manifest.

## Known Limits
- **Max Audio Length**: Recordings are hard-capped at 30 seconds.
- **Prompt Submissions**: Rate-limited to 20 prompts per user per 24 hours.
- **Bucket Restrictions**: Max file size is 5MB, strictly accepting `audio/wav`, `audio/x-wav`, and `audio/mp4`.
