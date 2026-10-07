/// Consent types for data assets.
enum ConsentTypeId {
  researchOnly('research_only'),
  commercialAi('commercial_ai'),
  open('open');

  const ConsentTypeId(this.value);
  final String value;

  static ConsentTypeId fromString(String s) =>
      ConsentTypeId.values.firstWhere((e) => e.value == s,
          orElse: () => ConsentTypeId.researchOnly);
}

class ConsentType {
  final String id;
  final String name;
  final String description;
  final bool allowsResearch;
  final bool allowsCommercial;
  final bool allowsOpenDistribution;

  const ConsentType({
    required this.id,
    required this.name,
    required this.description,
    required this.allowsResearch,
    required this.allowsCommercial,
    required this.allowsOpenDistribution,
  });

  factory ConsentType.fromJson(Map<String, dynamic> json) => ConsentType(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        allowsResearch: json['allows_research'] as bool? ?? true,
        allowsCommercial: json['allows_commercial'] as bool? ?? false,
        allowsOpenDistribution:
            json['allows_open_distribution'] as bool? ?? false,
      );
}


class Domain {
  final String id;
  final String name;
  final String? description;

  const Domain({required this.id, required this.name, this.description});

  factory Domain.fromJson(Map<String, dynamic> json) => Domain(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}


class Environment {
  final String id;
  final String name;
  final String? description;

  const Environment({required this.id, required this.name, this.description});

  factory Environment.fromJson(Map<String, dynamic> json) => Environment(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}


enum ReviewStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  needsRevision('needs_revision');

  const ReviewStatus(this.value);
  final String value;

  static ReviewStatus fromString(String s) =>
      ReviewStatus.values.firstWhere((e) => e.value == s,
          orElse: () => ReviewStatus.pending);
}


/// A DataAsset is the canonical representation of a piece of speech data.
/// It wraps a Recording with quality, consent, provenance, and review info.
class DataAsset {
  final String id;
  final String? recordingId;
  final String? transcript;
  final String? normalizedText;
  final int? dialectId;
  final String domainId;
  final String? environmentId;
  final String? contributorId;
  final String? speakerAgeBand;
  final String? speakerGender;
  final int? durationMs;
  final int? sampleRate;
  final int? channels;
  final int? fileSizeBytes;
  final String? audioFormat;
  final String? storagePath;
  final String consentTypeId;
  final DateTime? consentedAt;
  final ReviewStatus reviewStatus;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNotes;
  final int? qualityScore;
  final DateTime? qualityComputedAt;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DataAsset({
    required this.id,
    this.recordingId,
    this.transcript,
    this.normalizedText,
    this.dialectId,
    this.domainId = 'general',
    this.environmentId,
    this.contributorId,
    this.speakerAgeBand,
    this.speakerGender,
    this.durationMs,
    this.sampleRate,
    this.channels,
    this.fileSizeBytes,
    this.audioFormat,
    this.storagePath,
    this.consentTypeId = 'research_only',
    this.consentedAt,
    this.reviewStatus = ReviewStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNotes,
    this.qualityScore,
    this.qualityComputedAt,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DataAsset.fromJson(Map<String, dynamic> json) => DataAsset(
        id: json['id'] as String,
        recordingId: json['recording_id'] as String?,
        transcript: json['transcript'] as String?,
        normalizedText: json['normalized_text'] as String?,
        dialectId: json['dialect_id'] as int?,
        domainId: json['domain_id'] as String? ?? 'general',
        environmentId: json['environment_id'] as String?,
        contributorId: json['contributor_id'] as String?,
        speakerAgeBand: json['speaker_age_band'] as String?,
        speakerGender: json['speaker_gender'] as String?,
        durationMs: json['duration_ms'] as int?,
        sampleRate: json['sample_rate'] as int?,
        channels: json['channels'] as int?,
        fileSizeBytes: json['file_size_bytes'] as int?,
        audioFormat: json['audio_format'] as String?,
        storagePath: json['storage_path'] as String?,
        consentTypeId: json['consent_type_id'] as String? ?? 'research_only',
        consentedAt: json['consented_at'] != null
            ? DateTime.parse(json['consented_at'] as String)
            : null,
        reviewStatus: ReviewStatus.fromString(
            json['review_status'] as String? ?? 'pending'),
        reviewedBy: json['reviewed_by'] as String?,
        reviewedAt: json['reviewed_at'] != null
            ? DateTime.parse(json['reviewed_at'] as String)
            : null,
        reviewNotes: json['review_notes'] as String?,
        qualityScore: json['quality_score'] as int?,
        qualityComputedAt: json['quality_computed_at'] != null
            ? DateTime.parse(json['quality_computed_at'] as String)
            : null,
        isDeleted: json['is_deleted'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'recording_id': recordingId,
        'transcript': transcript,
        'normalized_text': normalizedText,
        'dialect_id': dialectId,
        'domain_id': domainId,
        'environment_id': environmentId,
        'contributor_id': contributorId,
        'speaker_age_band': speakerAgeBand,
        'speaker_gender': speakerGender,
        'duration_ms': durationMs,
        'sample_rate': sampleRate,
        'channels': channels,
        'file_size_bytes': fileSizeBytes,
        'audio_format': audioFormat,
        'storage_path': storagePath,
        'consent_type_id': consentTypeId,
        'consented_at': consentedAt?.toIso8601String(),
      };
}


/// Individual quality check signals for a DataAsset.
/// Scores are REAL — computed from actual audio analysis.
/// Fields that require unavailable ML providers are null.
class DataAssetQualityChecks {
  final String id;
  final String dataAssetId;
  // Format
  final bool? formatValid;
  final int? sampleRateHz;
  final int? channels;
  final int? bitDepth;
  final int? durationMs;
  final int? fileSizeBytes;
  // Content
  final bool? speechPresence;
  final double? silenceRatio;
  final bool? clippingDetected;
  // Volume
  final double? peakAmplitudeDb;
  final double? rmsDb;
  // Duplicate detection
  final String? audioSha256;
  // Scores (0-100)
  final int? audioQualityScore;
  final int? metadataQualityScore;
  final int? consentQualityScore;
  final int? overallQualityScore;
  // Advanced analysis status
  final String advancedAnalysisStatus;
  // Explanations
  final List<QualityExplanationItem> qualityExplanation;
  final DateTime computedAt;

  const DataAssetQualityChecks({
    required this.id,
    required this.dataAssetId,
    this.formatValid,
    this.sampleRateHz,
    this.channels,
    this.bitDepth,
    this.durationMs,
    this.fileSizeBytes,
    this.speechPresence,
    this.silenceRatio,
    this.clippingDetected,
    this.peakAmplitudeDb,
    this.rmsDb,
    this.audioSha256,
    this.audioQualityScore,
    this.metadataQualityScore,
    this.consentQualityScore,
    this.overallQualityScore,
    this.advancedAnalysisStatus = 'unavailable',
    this.qualityExplanation = const [],
    required this.computedAt,
  });

  factory DataAssetQualityChecks.fromJson(Map<String, dynamic> json) =>
      DataAssetQualityChecks(
        id: json['id'] as String,
        dataAssetId: json['data_asset_id'] as String,
        formatValid: json['format_valid'] as bool?,
        sampleRateHz: json['sample_rate_hz'] as int?,
        channels: json['channels'] as int?,
        bitDepth: json['bit_depth'] as int?,
        durationMs: json['duration_ms'] as int?,
        fileSizeBytes: json['file_size_bytes'] as int?,
        speechPresence: json['speech_presence'] as bool?,
        silenceRatio: (json['silence_ratio'] as num?)?.toDouble(),
        clippingDetected: json['clipping_detected'] as bool?,
        peakAmplitudeDb: (json['peak_amplitude_db'] as num?)?.toDouble(),
        rmsDb: (json['rms_db'] as num?)?.toDouble(),
        audioSha256: json['audio_sha256'] as String?,
        audioQualityScore: json['audio_quality_score'] as int?,
        metadataQualityScore: json['metadata_quality_score'] as int?,
        consentQualityScore: json['consent_quality_score'] as int?,
        overallQualityScore: json['overall_quality_score'] as int?,
        advancedAnalysisStatus:
            json['advanced_analysis_status'] as String? ?? 'unavailable',
        qualityExplanation: (json['quality_explanation'] as List<dynamic>?)
                ?.map((e) => QualityExplanationItem.fromJson(
                    e as Map<String, dynamic>))
                .toList() ??
            [],
        computedAt: DateTime.parse(json['computed_at'] as String),
      );
}


class QualityExplanationItem {
  final String check;
  final bool passed;
  final String message;

  const QualityExplanationItem({
    required this.check,
    required this.passed,
    required this.message,
  });

  factory QualityExplanationItem.fromJson(Map<String, dynamic> json) =>
      QualityExplanationItem(
        check: json['check'] as String,
        passed: json['passed'] as bool,
        message: json['message'] as String,
      );

  Map<String, dynamic> toJson() => {
        'check': check,
        'passed': passed,
        'message': message,
      };
}


class ProvenanceEvent {
  final String id;
  final String dataAssetId;
  final String eventType;
  final String? actorId;
  final Map<String, dynamic> eventData;
  final DateTime occurredAt;

  const ProvenanceEvent({
    required this.id,
    required this.dataAssetId,
    required this.eventType,
    this.actorId,
    this.eventData = const {},
    required this.occurredAt,
  });

  factory ProvenanceEvent.fromJson(Map<String, dynamic> json) =>
      ProvenanceEvent(
        id: json['id'] as String,
        dataAssetId: json['data_asset_id'] as String,
        eventType: json['event_type'] as String,
        actorId: json['actor_id'] as String?,
        eventData:
            (json['event_data'] as Map<String, dynamic>?) ?? {},
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );
}


enum MissionTaskType {
  recording('recording'),
  transcriptionReview('transcription_review'),
  metadataValidation('metadata_validation'),
  dialectValidation('dialect_validation');

  const MissionTaskType(this.value);
  final String value;

  static MissionTaskType fromString(String s) =>
      MissionTaskType.values.firstWhere((e) => e.value == s,
          orElse: () => MissionTaskType.recording);
}

enum MissionStatus {
  draft('draft'),
  active('active'),
  paused('paused'),
  completed('completed'),
  cancelled('cancelled');

  const MissionStatus(this.value);
  final String value;

  static MissionStatus fromString(String s) =>
      MissionStatus.values.firstWhere((e) => e.value == s,
          orElse: () => MissionStatus.active);
}

class Mission {
  final String id;
  final String title;
  final String description;
  final MissionTaskType taskType;
  final MissionStatus status;
  final String? createdBy;
  final int? requiredDialectId;
  final String? requiredDomainId;
  final String? requiredEnvironmentId;
  final String? requiredAgeBand;
  final int targetQuantity;
  final int completedQuantity;
  final int? qualityThreshold;
  final int? minDurationMs;
  final int? maxDurationMs;
  final int priority;
  final bool isFeatured;
  final List<String> tags;
  final String? instructionsMarkdown;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Mission({
    required this.id,
    required this.title,
    required this.description,
    required this.taskType,
    required this.status,
    this.createdBy,
    this.requiredDialectId,
    this.requiredDomainId,
    this.requiredEnvironmentId,
    this.requiredAgeBand,
    this.targetQuantity = 10,
    this.completedQuantity = 0,
    this.qualityThreshold,
    this.minDurationMs,
    this.maxDurationMs,
    this.priority = 5,
    this.isFeatured = false,
    this.tags = const [],
    this.instructionsMarkdown,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isComplete => completedQuantity >= targetQuantity;
  double get progressFraction =>
      targetQuantity > 0 ? (completedQuantity / targetQuantity).clamp(0.0, 1.0) : 0.0;

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        taskType: MissionTaskType.fromString(json['task_type'] as String),
        status: MissionStatus.fromString(json['status'] as String),
        createdBy: json['created_by'] as String?,
        requiredDialectId: json['required_dialect_id'] as int?,
        requiredDomainId: json['required_domain_id'] as String?,
        requiredEnvironmentId: json['required_environment_id'] as String?,
        requiredAgeBand: json['required_age_band'] as String?,
        targetQuantity: json['target_quantity'] as int? ?? 10,
        completedQuantity: json['completed_quantity'] as int? ?? 0,
        qualityThreshold: json['quality_threshold'] as int?,
        minDurationMs: json['min_duration_ms'] as int?,
        maxDurationMs: json['max_duration_ms'] as int?,
        priority: json['priority'] as int? ?? 5,
        isFeatured: json['is_featured'] as bool? ?? false,
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        instructionsMarkdown: json['instructions_markdown'] as String?,
        startsAt: json['starts_at'] != null
            ? DateTime.parse(json['starts_at'] as String)
            : null,
        endsAt: json['ends_at'] != null
            ? DateTime.parse(json['ends_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}


class Dataset {
  final String id;
  final String name;
  final String? description;
  final String? createdBy;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Dataset({
    required this.id,
    required this.name,
    this.description,
    this.createdBy,
    this.isPublic = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Dataset.fromJson(Map<String, dynamic> json) => Dataset(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        createdBy: json['created_by'] as String?,
        isPublic: json['is_public'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}


class DatasetVersion {
  final String id;
  final String datasetId;
  final String version;
  final String? description;
  final Map<String, dynamic> filterCriteria;
  final int assetCount;
  final int totalDurationMs;
  final int speakerCount;
  final Map<String, dynamic> dialectDistribution;
  final Map<String, dynamic> domainDistribution;
  final double? averageQualityScore;
  final Map<String, dynamic> consentSummary;
  final bool isPublished;
  final DateTime? publishedAt;
  final String? createdBy;
  final DateTime createdAt;

  const DatasetVersion({
    required this.id,
    required this.datasetId,
    required this.version,
    this.description,
    this.filterCriteria = const {},
    this.assetCount = 0,
    this.totalDurationMs = 0,
    this.speakerCount = 0,
    this.dialectDistribution = const {},
    this.domainDistribution = const {},
    this.averageQualityScore,
    this.consentSummary = const {},
    this.isPublished = false,
    this.publishedAt,
    this.createdBy,
    required this.createdAt,
  });

  Duration get totalDuration => Duration(milliseconds: totalDurationMs);
  double get totalHours => totalDurationMs / (1000 * 3600);

  factory DatasetVersion.fromJson(Map<String, dynamic> json) => DatasetVersion(
        id: json['id'] as String,
        datasetId: json['dataset_id'] as String,
        version: json['version'] as String,
        description: json['description'] as String?,
        filterCriteria:
            (json['filter_criteria'] as Map<String, dynamic>?) ?? {},
        assetCount: json['asset_count'] as int? ?? 0,
        totalDurationMs: (json['total_duration_ms'] as num?)?.toInt() ?? 0,
        speakerCount: json['speaker_count'] as int? ?? 0,
        dialectDistribution:
            (json['dialect_distribution'] as Map<String, dynamic>?) ?? {},
        domainDistribution:
            (json['domain_distribution'] as Map<String, dynamic>?) ?? {},
        averageQualityScore:
            (json['average_quality_score'] as num?)?.toDouble(),
        consentSummary:
            (json['consent_summary'] as Map<String, dynamic>?) ?? {},
        isPublished: json['is_published'] as bool? ?? false,
        publishedAt: json['published_at'] != null
            ? DateTime.parse(json['published_at'] as String)
            : null,
        createdBy: json['created_by'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}


class ModelEvaluation {
  final String id;
  final String benchmarkVersionId;
  final String? evaluatorId;
  final String modelName;
  final String? modelVersion;
  final String? modelDescription;
  final double? overallWer;
  final double? overallCer;
  final Map<String, dynamic> categoryMetrics;
  final Map<String, dynamic> failureSummary;
  final String status;
  final String? errorMessage;
  final String? predictionsStoragePath;
  final DateTime createdAt;
  final DateTime? completedAt;

  const ModelEvaluation({
    required this.id,
    required this.benchmarkVersionId,
    this.evaluatorId,
    required this.modelName,
    this.modelVersion,
    this.modelDescription,
    this.overallWer,
    this.overallCer,
    this.categoryMetrics = const {},
    this.failureSummary = const {},
    required this.status,
    this.errorMessage,
    this.predictionsStoragePath,
    required this.createdAt,
    this.completedAt,
  });

  factory ModelEvaluation.fromJson(Map<String, dynamic> json) =>
      ModelEvaluation(
        id: json['id'] as String,
        benchmarkVersionId: json['benchmark_version_id'] as String,
        evaluatorId: json['evaluator_id'] as String?,
        modelName: json['model_name'] as String,
        modelVersion: json['model_version'] as String?,
        modelDescription: json['model_description'] as String?,
        overallWer: (json['overall_wer'] as num?)?.toDouble(),
        overallCer: (json['overall_cer'] as num?)?.toDouble(),
        categoryMetrics:
            (json['category_metrics'] as Map<String, dynamic>?) ?? {},
        failureSummary:
            (json['failure_summary'] as Map<String, dynamic>?) ?? {},
        status: json['status'] as String? ?? 'pending',
        errorMessage: json['error_message'] as String?,
        predictionsStoragePath: json['predictions_storage_path'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
      );
}


class EvaluationResult {
  final String id;
  final String evaluationId;
  final String benchmarkItemId;
  final String? hypothesis;
  final String reference;
  final double? wer;
  final double? cer;
  final int substitutions;
  final int deletions;
  final int insertions;

  const EvaluationResult({
    required this.id,
    required this.evaluationId,
    required this.benchmarkItemId,
    this.hypothesis,
    required this.reference,
    this.wer,
    this.cer,
    this.substitutions = 0,
    this.deletions = 0,
    this.insertions = 0,
  });

  factory EvaluationResult.fromJson(Map<String, dynamic> json) =>
      EvaluationResult(
        id: json['id'] as String,
        evaluationId: json['evaluation_id'] as String,
        benchmarkItemId: json['benchmark_item_id'] as String,
        hypothesis: json['hypothesis'] as String?,
        reference: json['reference'] as String,
        wer: (json['wer'] as num?)?.toDouble(),
        cer: (json['cer'] as num?)?.toDouble(),
        substitutions: json['substitutions'] as int? ?? 0,
        deletions: json['deletions'] as int? ?? 0,
        insertions: json['insertions'] as int? ?? 0,
      );
}
