import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/recording_entry.dart';
import '../models/contributor.dart';

const String kSupabaseUrl = 'https://YOUR-PROJECT-REF.supabase.co';
const String kSupabaseAnonKey = 'YOUR-ANON-PUBLIC-KEY';

const String kBucketName = 'audio-clips';
const String kTableName = 'recordings';
const String kContributorsTable = 'contributors';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    try {
      await Supabase.initialize(
        url: kSupabaseUrl,
        anonKey: kSupabaseAnonKey,
      );
    } catch (e) {
      // Catch initialization errors (e.g. network down)
      print('Supabase init failed: $e');
    }
  }

  /// Signs in anonymously and returns the user ID.
  Future<String> signInAnonymously() async {
    final session = client.auth.currentSession;
    if (session == null) {
      final response = await client.auth.signInAnonymously();
      return response.user!.id;
    }
    return session.user.id;
  }

  String? get currentUserId => client.auth.currentUser?.id;

  /// Fetches the current operator's profile if it exists.
  Future<Contributor?> getOperatorProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final data = await client
          .from(kContributorsTable)
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (data == null) return null;
      return Contributor.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// Saves or updates the operator's profile.
  Future<void> saveOperatorProfile(Contributor profile) async {
    await client.from(kContributorsTable).upsert(profile.toJson());
  }

  /// Validates that the bucket and tables are accessible.
  Future<void> validateConfiguration() async {
    try {
      // Attempt a lightweight fetch to verify the table exists
      await client.from(kTableName).select('id').limit(1);
    } catch (e) {
      throw Exception('Database tables are misconfigured or missing.');
    }

    try {
      // Verify bucket exists by getting public URL for a dummy file
      client.storage.from(kBucketName).getPublicUrl('dummy.m4a');
    } catch (e) {
      throw Exception('Storage bucket is misconfigured or missing.');
    }
  }

  Future<String> uploadRecording({
    required File audioFile,
    required String prompt,
    required Contributor speaker, // can be operator or 3rd party
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Operator not authenticated');

    await validateConfiguration();

    final id = const Uuid().v4();
    final storagePath = '${speaker.dialect}/$id.m4a';

    await client.storage.from(kBucketName).upload(
      storagePath,
      audioFile,
      fileOptions: const FileOptions(
        contentType: 'audio/m4a',
        upsert: false,
      ),
    );

    final entry = RecordingEntry(
      prompt: prompt,
      storagePath: storagePath,
      operatorId: uid,
      speakerName: speaker.name,
      speakerAge: speaker.age,
      speakerPlace: speaker.place,
      speakerDialect: speaker.dialect,
    );

    await client.from(kTableName).insert(entry.toJson());

    return client.storage.from(kBucketName).getPublicUrl(storagePath);
  }

  Future<List<RecordingEntry>> fetchRecordings() async {
    await validateConfiguration();
    
    final rows = await client
        .from(kTableName)
        .select()
        .order('created_at', ascending: false);
        
    return rows.map((row) => RecordingEntry.fromJson(row)).toList();
  }

  String publicUrlFor(String storagePath) {
    return client.storage.from(kBucketName).getPublicUrl(storagePath);
  }
}