import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/recording.dart';
import '../../domain/repositories/recording_repository.dart';

class SupabaseRecordingRepository implements RecordingRepository {
  final SupabaseClient client;
  final String bucketName = 'audio-clips';

  SupabaseRecordingRepository(this.client);

  @override
  Future<Recording> saveRecording(Recording recording, File audioFile) async {
    // 1. Upload to storage
    final storagePath = recording.storagePath;
    await client.storage.from(bucketName).upload(
          storagePath,
          audioFile,
          fileOptions: const FileOptions(
            contentType: 'audio/m4a',
            upsert: false,
          ),
        );

    // 2. Insert into DB
    final data = {
      'contributor_id': recording.contributorId,
      'prompt_id': recording.promptId,
      'storage_path': storagePath,
      'duration_ms': recording.durationMs,
      'file_size_bytes': recording.fileSizeBytes,
      'audio_format': recording.audioFormat,
      'sample_rate': recording.sampleRate,
      'channels': recording.channels,
      'upload_status': RecordingUploadStatus.uploaded.name,
      'review_status': RecordingReviewStatus.pending.name,
    };

    final response = await client.from('recordings').insert(data).select().single();
    return _fromJson(response);
  }

  @override
  Future<List<Recording>> getRecordingsForContributor(String contributorId) async {
    final response = await client
        .from('recordings')
        .select()
        .eq('contributor_id', contributorId)
        .order('created_at', ascending: false);
    return (response as List).map((json) => _fromJson(json)).toList();
  }

  @override
  Future<void> updateUploadStatus(String id, RecordingUploadStatus status) async {
    await client
        .from('recordings')
        .update({'upload_status': status.name})
        .eq('id', id);
  }

  Recording _fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] as String,
      contributorId: json['contributor_id'] as String,
      promptId: json['prompt_id'] as String,
      storagePath: json['storage_path'] as String,
      durationMs: json['duration_ms'] as int,
      fileSizeBytes: json['file_size_bytes'] as int,
      audioFormat: json['audio_format'] as String,
      sampleRate: json['sample_rate'] as int,
      channels: json['channels'] as int,
      uploadStatus: RecordingUploadStatus.values.firstWhere((e) => e.name == json['upload_status'], orElse: () => RecordingUploadStatus.uploaded),
      reviewStatus: RecordingReviewStatus.values.firstWhere((e) => e.name == json['review_status'], orElse: () => RecordingReviewStatus.pending),
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }
}
