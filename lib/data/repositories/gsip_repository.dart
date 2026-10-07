import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/gsip_models.dart';
import '../../services/quality_engine.dart';

/// Repository handling all Supabase interactions for the Gujarati Speech Intelligence Platform (GSIP).
class GsipRepository {
  final SupabaseClient _client;

  GsipRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // ──────────────────────────────────────────────────────────────────────────
  // 1. MISSIONS
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Mission>> fetchMissions({
    String? status = 'active',
    MissionTaskType? taskType,
    int? dialectId,
  }) async {
    try {
      var query = _client.from('missions').select();
      if (status != null) {
        query = query.eq('status', status);
      }
      if (taskType != null) {
        query = query.eq('task_type', taskType.value);
      }
      if (dialectId != null) {
        query = query.eq('required_dialect_id', dialectId);
      }

      final res = await query.order('priority', ascending: false);
      return (res as List<dynamic>)
          .map((json) => Mission.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching missions: $e');
      rethrow;
    }
  }

  Future<Mission> createMission(Mission mission) async {
    try {
      final data = <String, dynamic>{
        'title': mission.title,
        'description': mission.description,
        'task_type': mission.taskType.value,
        'status': mission.status.value,
        'created_by': currentUserId,
        'target_quantity': mission.targetQuantity,
        'completed_quantity': mission.completedQuantity,
        'priority': mission.priority,
        'is_featured': mission.isFeatured,
        'tags': mission.tags,
      };

      if (mission.requiredDialectId != null) {
        data['required_dialect_id'] = mission.requiredDialectId;
      }
      if (mission.requiredDomainId != null) {
        data['required_domain_id'] = mission.requiredDomainId;
      }
      if (mission.requiredEnvironmentId != null) {
        data['required_environment_id'] = mission.requiredEnvironmentId;
      }
      if (mission.requiredAgeBand != null) {
        data['required_age_band'] = mission.requiredAgeBand;
      }
      if (mission.qualityThreshold != null) {
        data['quality_threshold'] = mission.qualityThreshold;
      }
      if (mission.instructionsMarkdown != null) {
        data['instructions_markdown'] = mission.instructionsMarkdown;
      }

      final res = await _client.from('missions').insert(data).select().single();
      return Mission.fromJson(res);
    } catch (e) {
      debugPrint('Error creating mission: $e');
      rethrow;
    }
  }

  Future<void> submitToMission({
    required String missionId,
    required String dataAssetId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not authenticated');

    await _client.from('mission_submissions').insert({
      'mission_id': missionId,
      'data_asset_id': dataAssetId,
      'contributor_id': uid,
      'submission_status': 'submitted',
    });

    // Increment completed_quantity atomically via RPC or fallback update
    try {
      await _client.rpc('increment_mission_count', params: {'mission_id': missionId});
    } catch (_) {
      final missionRow = await _client
          .from('missions')
          .select('completed_quantity')
          .eq('id', missionId)
          .single();
      final current = (missionRow['completed_quantity'] as int?) ?? 0;
      await _client
          .from('missions')
          .update({'completed_quantity': current + 1})
          .eq('id', missionId);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. DATA ASSETS & QUALITY
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<DataAsset>> fetchDataAssets({
    ReviewStatus? reviewStatus,
    int? dialectId,
    String? domainId,
    String? environmentId,
    int? minQuality,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _client.from('data_assets').select().eq('is_deleted', false);

      if (reviewStatus != null) {
        query = query.eq('review_status', reviewStatus.value);
      }
      if (dialectId != null) {
        query = query.eq('dialect_id', dialectId);
      }
      if (domainId != null) {
        query = query.eq('domain_id', domainId);
      }
      if (environmentId != null) {
        query = query.eq('environment_id', environmentId);
      }
      if (minQuality != null) {
        query = query.gte('quality_score', minQuality);
      }

      final res = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (res as List<dynamic>)
          .map((json) => DataAsset.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching data assets: $e');
      rethrow;
    }
  }

  Future<DataAssetQualityChecks?> fetchQualityChecks(String dataAssetId) async {
    try {
      final res = await _client
          .from('data_asset_quality_checks')
          .select()
          .eq('data_asset_id', dataAssetId)
          .maybeSingle();

      if (res == null) return null;
      return DataAssetQualityChecks.fromJson(res);
    } catch (e) {
      debugPrint('Error fetching quality checks: $e');
      return null;
    }
  }

  Future<DataAsset> createDataAsset({
    required String? recordingId,
    required String? transcript,
    required int? dialectId,
    String domainId = 'general',
    String? environmentId,
    String? speakerAgeBand,
    String? speakerGender,
    int? durationMs,
    int? sampleRate,
    int? channels,
    int? fileSizeBytes,
    String? audioFormat,
    String? storagePath,
    String consentTypeId = 'research_only',
    QualityAnalysis? qualityAnalysis,
  }) async {
    final uid = currentUserId;
    final now = DateTime.now();

    final assetData = <String, dynamic>{
      'domain_id': domainId,
      'contributor_id': uid,
      'consent_type_id': consentTypeId,
      'consented_at': now.toIso8601String(),
      'review_status': 'pending',
    };

    if (recordingId != null) assetData['recording_id'] = recordingId;
    if (transcript != null) assetData['transcript'] = transcript;
    if (dialectId != null) assetData['dialect_id'] = dialectId;
    if (environmentId != null) assetData['environment_id'] = environmentId;
    if (speakerAgeBand != null) assetData['speaker_age_band'] = speakerAgeBand;
    if (speakerGender != null) assetData['speaker_gender'] = speakerGender;
    if (durationMs != null) assetData['duration_ms'] = durationMs;
    if (sampleRate != null) assetData['sample_rate'] = sampleRate;
    if (channels != null) assetData['channels'] = channels;
    if (fileSizeBytes != null) assetData['file_size_bytes'] = fileSizeBytes;
    if (audioFormat != null) assetData['audio_format'] = audioFormat;
    if (storagePath != null) assetData['storage_path'] = storagePath;

    if (qualityAnalysis?.overallQualityScore != null) {
      assetData['quality_score'] = qualityAnalysis!.overallQualityScore;
    }
    if (qualityAnalysis != null) {
      assetData['quality_computed_at'] = qualityAnalysis.computedAt.toIso8601String();
    }

    final assetRes = await _client
        .from('data_assets')
        .insert(assetData)
        .select()
        .single();

    final asset = DataAsset.fromJson(assetRes);

    // Save individual quality checks if analysis was performed
    if (qualityAnalysis != null) {
      final checksData = qualityAnalysis.toQualityChecksJson(asset.id);
      try {
        await _client.from('data_asset_quality_checks').insert(checksData);
      } catch (e) {
        debugPrint('Warning: could not insert quality checks: $e');
      }
    }

    // Record provenance event
    await recordProvenanceEvent(
      dataAssetId: asset.id,
      eventType: 'recorded',
      eventData: {
        'duration_ms': durationMs,
        'domain_id': domainId,
        'quality_score': qualityAnalysis?.overallQualityScore,
      },
    );

    return asset;
  }

  Future<void> updateReviewStatus({
    required String assetId,
    required ReviewStatus status,
    String? notes,
  }) async {
    final uid = currentUserId;
    final now = DateTime.now();

    final updateData = <String, dynamic>{
      'review_status': status.value,
      'reviewed_by': uid,
      'reviewed_at': now.toIso8601String(),
    };
    if (notes != null) {
      updateData['review_notes'] = notes;
    }

    await _client.from('data_assets').update(updateData).eq('id', assetId);

    final eventData = <String, dynamic>{'status': status.value};
    if (notes != null) {
      eventData['notes'] = notes;
    }

    await recordProvenanceEvent(
      dataAssetId: assetId,
      eventType: status == ReviewStatus.approved ? 'approved' : 'rejected',
      eventData: eventData,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. PROVENANCE
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> recordProvenanceEvent({
    required String dataAssetId,
    required String eventType,
    Map<String, dynamic> eventData = const {},
  }) async {
    try {
      await _client.from('provenance_events').insert({
        'data_asset_id': dataAssetId,
        'event_type': eventType,
        'actor_id': currentUserId,
        'event_data': eventData,
        'occurred_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Warning: failed to record provenance event: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. DATASETS & VERSIONING
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Dataset>> fetchDatasets() async {
    final res = await _client
        .from('datasets')
        .select()
        .order('created_at', ascending: false);

    return (res as List<dynamic>)
        .map((json) => Dataset.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Dataset> createDataset({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    final insertData = <String, dynamic>{
      'name': name,
      'is_public': isPublic,
      'created_by': currentUserId,
    };
    if (description != null) {
      insertData['description'] = description;
    }

    final res = await _client.from('datasets').insert(insertData).select().single();
    return Dataset.fromJson(res);
  }

  Future<List<DatasetVersion>> fetchDatasetVersions(String datasetId) async {
    final res = await _client
        .from('dataset_versions')
        .select()
        .eq('dataset_id', datasetId)
        .order('created_at', ascending: false);

    return (res as List<dynamic>)
        .map((json) => DatasetVersion.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<DatasetVersion> createDatasetVersion({
    required String datasetId,
    required String version,
    String? description,
    required Map<String, dynamic> filterCriteria,
    required List<String> assetIds,
    required int assetCount,
    required int totalDurationMs,
    required int speakerCount,
    required Map<String, dynamic> dialectDistribution,
    required Map<String, dynamic> domainDistribution,
    double? averageQualityScore,
    required Map<String, dynamic> consentSummary,
  }) async {
    final versionData = <String, dynamic>{
      'dataset_id': datasetId,
      'version': version,
      'filter_criteria': filterCriteria,
      'asset_count': assetCount,
      'total_duration_ms': totalDurationMs,
      'speaker_count': speakerCount,
      'dialect_distribution': dialectDistribution,
      'domain_distribution': domainDistribution,
      'consent_summary': consentSummary,
      'is_published': false,
      'created_by': currentUserId,
    };

    if (description != null) {
      versionData['description'] = description;
    }
    if (averageQualityScore != null) {
      versionData['average_quality_score'] = averageQualityScore;
    }

    final row = await _client.from('dataset_versions').insert(versionData).select().single();
    final dv = DatasetVersion.fromJson(row);

    // Link assets to version
    if (assetIds.isNotEmpty) {
      final inserts = assetIds.map((aId) => {
        'dataset_version_id': dv.id,
        'data_asset_id': aId,
      }).toList();

      await _client.from('dataset_version_assets').insert(inserts);
    }

    return dv;
  }

  Future<void> publishDatasetVersion(String versionId) async {
    await _client.from('dataset_versions').update({
      'is_published': true,
      'published_at': DateTime.now().toIso8601String(),
    }).eq('id', versionId);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 5. BENCHMARKS & EVALUATIONS
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchBenchmarks() async {
    final res = await _client
        .from('benchmarks')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<List<Map<String, dynamic>>> fetchBenchmarkVersions(String benchmarkId) async {
    final res = await _client
        .from('benchmark_versions')
        .select()
        .eq('benchmark_id', benchmarkId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<List<Map<String, dynamic>>> fetchBenchmarkItems(String benchmarkVersionId) async {
    final res = await _client
        .from('benchmark_items')
        .select()
        .eq('benchmark_version_id', benchmarkVersionId)
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<ModelEvaluation> recordModelEvaluation({
    required String benchmarkVersionId,
    required String modelName,
    String? modelVersion,
    String? modelDescription,
    required double overallWer,
    required double overallCer,
    required Map<String, dynamic> categoryMetrics,
    required Map<String, dynamic> failureSummary,
    required List<EvaluationResult> results,
  }) async {
    final evalData = <String, dynamic>{
      'benchmark_version_id': benchmarkVersionId,
      'evaluator_id': currentUserId,
      'model_name': modelName,
      'overall_wer': overallWer,
      'overall_cer': overallCer,
      'category_metrics': categoryMetrics,
      'failure_summary': failureSummary,
      'status': 'complete',
      'completed_at': DateTime.now().toIso8601String(),
    };

    if (modelVersion != null) evalData['model_version'] = modelVersion;
    if (modelDescription != null) evalData['model_description'] = modelDescription;

    final evalRow = await _client.from('model_evaluations').insert(evalData).select().single();
    final eval = ModelEvaluation.fromJson(evalRow);

    // Save individual item evaluation results
    if (results.isNotEmpty) {
      final inserts = results.map((r) {
        final row = <String, dynamic>{
          'evaluation_id': eval.id,
          'benchmark_item_id': r.benchmarkItemId,
          'reference': r.reference,
          'wer': r.wer,
          'cer': r.cer,
          'substitutions': r.substitutions,
          'deletions': r.deletions,
          'insertions': r.insertions,
        };
        if (r.hypothesis != null) row['hypothesis'] = r.hypothesis;
        return row;
      }).toList();

      await _client.from('evaluation_results').insert(inserts);
    }

    return eval;
  }

  Future<List<ModelEvaluation>> fetchModelEvaluations({
    String? benchmarkVersionId,
  }) async {
    var query = _client.from('model_evaluations').select();
    if (benchmarkVersionId != null) {
      query = query.eq('benchmark_version_id', benchmarkVersionId);
    }
    final res = await query.order('created_at', ascending: false);
    return (res as List<dynamic>)
        .map((json) => ModelEvaluation.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6. DATA PROJECTS
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchDataProjects() async {
    final res = await _client
        .from('data_projects')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<Map<String, dynamic>> createDataProject({
    required String name,
    String? description,
    required Map<String, dynamic> requirements,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('User not authenticated');

    final projectData = <String, dynamic>{
      'name': name,
      'owner_id': uid,
      'requirements': requirements,
      'status': 'active',
    };
    if (description != null) {
      projectData['description'] = description;
    }

    final res = await _client.from('data_projects').insert(projectData).select().single();
    return Map<String, dynamic>.from(res as Map);
  }
}
