import 'dart:io';
import '../entities/recording.dart';

abstract class RecordingRepository {
  Future<Recording> saveRecording(Recording recording, File audioFile);
  Future<List<Recording>> getRecordingsForContributor(String contributorId);
  Future<void> updateUploadStatus(String id, RecordingUploadStatus status);
}
