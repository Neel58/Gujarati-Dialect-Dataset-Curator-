import 'package:equatable/equatable.dart';

enum RecordingUploadStatus { draft, uploading, uploaded, failed }
enum RecordingReviewStatus { pending, approved, rejected }

class Recording extends Equatable {
  final String id;
  final String contributorId;
  final String promptId;
  final String storagePath;
  final int durationMs;
  final int fileSizeBytes;
  final String audioFormat;
  final int sampleRate;
  final int channels;
  final RecordingUploadStatus uploadStatus;
  final RecordingReviewStatus reviewStatus;
  final String? rejectionReason;
  final DateTime? createdAt;

  const Recording({
    required this.id,
    required this.contributorId,
    required this.promptId,
    required this.storagePath,
    required this.durationMs,
    required this.fileSizeBytes,
    required this.audioFormat,
    required this.sampleRate,
    required this.channels,
    this.uploadStatus = RecordingUploadStatus.draft,
    this.reviewStatus = RecordingReviewStatus.pending,
    this.rejectionReason,
    this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        contributorId,
        promptId,
        storagePath,
        durationMs,
        fileSizeBytes,
        audioFormat,
        sampleRate,
        channels,
        uploadStatus,
        reviewStatus,
        rejectionReason,
        createdAt,
      ];
}
