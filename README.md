# Gujarati Dialect Curator

Flutter app that shows a Gujarati prompt, records a contributor reading it aloud,
collects metadata (name, age, place, dialect), and uploads both to Supabase.

## 1. Create the Supabase project (5 min)

1. Go to https://supabase.com → New project (free tier, no card needed).
2. Once created, go to **SQL Editor** → paste the contents of `supabase_setup.sql` → Run.
   This creates the `recordings` metadata table with RLS policies open enough for a demo.
3. Go to **Storage** → Create a new bucket named exactly `audio-clips` → mark it **Public**
   (so playback URLs work without extra auth for the demo).
4. Go to **Project Settings → API** → copy:
   - `Project URL`
   - `anon public` key

## 2. Wire up the app

Open `lib/services/supabase_service.dart` and replace:

```dart
const String kSupabaseUrl = 'https://YOUR-PROJECT-REF.supabase.co';
const String kSupabaseAnonKey = 'YOUR-ANON-PUBLIC-KEY';
```

with the values from step 1.

## 3. Install and run

```bash
flutter pub get
flutter run
```

### Android permissions
Add to `android/app/src/main/AndroidManifest.xml` (inside `<manifest>`, above `<application>`):

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS permissions
Add to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record dialect samples.</string>
```

## How it works

- `lib/data/prompts.dart` — the list of Gujarati sentences shown to contributors.
  Edit this list to add your own prompts.
- Home screen → tap a prompt → record screen: record audio, fill in
  name/age/place/dialect, submit.
- On submit: audio uploads to the `audio-clips` bucket as `.m4a`, and a row goes
  into the `recordings` table with the storage path.
- "Review uploads" (top-right icon on home screen) lists every submission and lets
  you play it back inline — this is the screen to show your teacher.

## Known limits (be upfront about these if asked)

- Supabase free tier: 1 GB storage, projects auto-pause after 7 days of no activity.
  Fine for a demo, not for real crowdsourcing at scale.
- RLS policies here allow anyone with the anon key to insert/read — acceptable for
  a classroom demo, not for a public release. Lock this down before wider distribution.
