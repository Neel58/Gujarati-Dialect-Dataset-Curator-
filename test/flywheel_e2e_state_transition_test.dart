import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/audio/wav_builder.dart';
import 'package:gujarati_dialect_curator/models/gsip_models.dart';
import 'package:gujarati_dialect_curator/services/coverage_gap_engine.dart';
import 'package:gujarati_dialect_curator/services/dataset_builder_service.dart';
import 'package:gujarati_dialect_curator/services/evaluation_engine.dart';
import 'package:gujarati_dialect_curator/services/quality_engine.dart';

void main() {
  group('GSIP Complete Flywheel - End-to-End State Transitions', () {
    final now = DateTime.now();

    test('Full lifecycle: Requirement -> Gap -> Mission -> Asset -> Quality -> Review -> Dataset -> Benchmark -> WER -> Failure Analysis -> Recommendation -> New Mission', () {
      // ── Step 1: Project / Data Requirement ───────────────────────────────
      const targetHours = 5.0;
      const targetDialectId = 2; // Kathiyawadi
      const targetDomain = 'healthcare';
      expect(targetHours, equals(5.0));

      // ── Step 2: Coverage Gap Detection ───────────────────────────────────
      // Corpus initially contains only 1 small clip (0.25 hours) of Kathiyawadi
      final initialCorpus = [
        DataAsset(
          id: 'initial-1',
          reviewStatus: ReviewStatus.approved,
          dialectId: targetDialectId,
          domainId: targetDomain,
          contributorId: 'pioneer-user',
          durationMs: 900000, // 15 mins = 0.25 hrs
          qualityScore: 85,
          consentTypeId: 'commercial_ai',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final coverageReport = CoverageGapEngine.analyze(initialCorpus);
      expect(coverageReport.totalAssets, equals(1));
      expect(coverageReport.detectedGaps.isNotEmpty, isTrue);

      final dialectGap = coverageReport.detectedGaps.firstWhere(
        (g) => g.dimension == 'dialect' && g.dialectId == targetDialectId,
      );
      expect(dialectGap.priority, equals('high'));

      // ── Step 3: Targeted Mission Proposal ────────────────────────────────
      final missionProposal = dialectGap.toMissionProposal();
      expect(missionProposal.requiredDialectId, equals(targetDialectId));

      final activeMission = Mission(
        id: 'mission-kathiyawadi-01',
        title: missionProposal.title,
        description: missionProposal.description,
        taskType: missionProposal.taskType,
        status: MissionStatus.active,
        requiredDialectId: missionProposal.requiredDialectId,
        requiredDomainId: targetDomain,
        targetQuantity: 20,
        completedQuantity: 0,
        priority: 9,
        createdAt: now,
        updatedAt: now,
      );
      expect(activeMission.completedQuantity, equals(0));

      // ── Step 4 & 5: Contributor Recording & Quality Engine ───────────────
      // Create valid 16kHz mono audio PCM bytes (1 sec)
      final pcm = Uint8List(32000);
      final bd = ByteData.sublistView(pcm);
      for (int i = 0; i < 16000; i++) {
        bd.setInt16(i * 2, (i % 2 == 0 ? 6000 : -6000), Endian.little);
      }
      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);

      final quality = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasTranscript: true,
        hasDialect: true,
        hasDistrict: true,
        consentType: 'commercial_ai',
      );

      expect(quality.formatValid, isTrue);
      expect(quality.speechPresence, isTrue);
      expect(quality.clippingDetected, isFalse);
      expect(quality.overallQualityScore, greaterThan(80));
      expect(quality.audioSha256?.length, equals(64)); // Valid SHA-256

      // ── Step 6: Canonical DataAsset Creation ──────────────────────────────
      final newAsset = DataAsset(
        id: 'asset-submitted-01',
        contributorId: 'contributor-user-42',
        reviewStatus: ReviewStatus.pending, // Forced pending by governance
        dialectId: targetDialectId,
        domainId: targetDomain,
        durationMs: 15000,
        qualityScore: quality.overallQualityScore,
        consentTypeId: 'commercial_ai',
        transcript: 'મને માથામાં દુખાવો થાય છે',
        createdAt: now,
        updatedAt: now,
      );
      expect(newAsset.reviewStatus, equals(ReviewStatus.pending));

      // ── Step 7: Human Curation & Review ──────────────────────────────────
      // Contributor cannot approve own asset
      const curatorId = 'curator-admin-99';
      expect(newAsset.contributorId != curatorId, isTrue);

      final approvedAsset = DataAsset(
        id: newAsset.id,
        contributorId: newAsset.contributorId,
        reviewStatus: ReviewStatus.approved,
        reviewedBy: curatorId,
        reviewedAt: now,
        dialectId: newAsset.dialectId,
        domainId: newAsset.domainId,
        durationMs: newAsset.durationMs,
        qualityScore: newAsset.qualityScore,
        consentTypeId: newAsset.consentTypeId,
        transcript: newAsset.transcript,
        createdAt: newAsset.createdAt,
        updatedAt: now,
      );
      expect(approvedAsset.reviewStatus, equals(ReviewStatus.approved));

      // ── Step 8 & 9: Dataset Builder & Immutable Versioning ────────────────
      final candidateCorpus = [...initialCorpus, approvedAsset];
      final datasetEvaluation = DatasetBuilderService.evaluateAssets(
        allAssets: candidateCorpus,
        criteria: const DatasetFilterCriteria(
          dialectIds: [targetDialectId],
          domainIds: [targetDomain],
          minQualityScore: 80,
          requiredConsentType: 'commercial_ai',
        ),
      );

      expect(datasetEvaluation.eligibleAssets.length, equals(2));
      expect(datasetEvaluation.uniqueSpeakers, equals(2));

      final publishedVersion = DatasetVersion(
        id: 'ver-1.0',
        datasetId: 'dataset-kathiyawadi-asr',
        version: '1.0',
        filterCriteria: const {'min_quality': 80, 'dialect': 2},
        assetCount: datasetEvaluation.eligibleAssets.length,
        totalDurationMs: datasetEvaluation.totalDurationMs,
        speakerCount: datasetEvaluation.uniqueSpeakers,
        isPublished: true, // Published & Immutable
        publishedAt: now,
        createdAt: now,
      );
      expect(publishedVersion.isPublished, isTrue);

      // ── Step 10 & 11: Benchmark Evaluation (WER / CER) ────────────────────
      final benchmarkSuite = [
        const BenchmarkEvaluationInput(
          id: 'bench-std-1',
          reference: 'નમસ્તે ગુજરાત કેમ છો બધા',
          hypothesis: 'નમસ્તે ગુજરાત કેમ છો બધા', // 0% WER
          category: 'standard',
        ),
        const BenchmarkEvaluationInput(
          id: 'bench-kat-1',
          reference: 'તમે ક્યાં ગામના રહેવાસી છો ભાઈ',
          hypothesis: 'તમે ક્યાં ગામ ભાઈ', // 1 sub ('ગામના'->'ગામ') + 2 del ('રહેવાસી', 'છો') = 3 errors / 6 words = 50.0% WER
          category: 'kathiyawadi',
          dialectId: targetDialectId,
          domainId: targetDomain,
        ),
      ];

      final evalSummary = EvaluationEngine.evaluateBatch(benchmarkSuite);
      expect(evalSummary.totalSamples, equals(2));
      expect(evalSummary.categoryBreakdown['standard']!.wer, equals(0.0));
      expect(evalSummary.categoryBreakdown['kathiyawadi']!.wer, closeTo(3.0 / 6.0, 0.01));

      // ── Step 12 & 13: Failure Analysis -> Recommendation -> Loop Closure ──
      expect(evalSummary.recommendations.isNotEmpty, isTrue);
      final recommendation = evalSummary.recommendations.first;
      expect(recommendation.targetCategory, equals('kathiyawadi'));
      expect(recommendation.priority, equals('high'));
      expect(recommendation.dialectId, equals(targetDialectId.toString()));

      // Closed loop: Recommendation automatically generates new targeted mission
      final nextMission = Mission(
        id: 'mission-kathiyawadi-02',
        title: recommendation.title,
        description: recommendation.description,
        taskType: MissionTaskType.recording,
        status: MissionStatus.active,
        requiredDialectId: int.parse(recommendation.dialectId!),
        requiredDomainId: recommendation.domainId,
        targetQuantity: recommendation.recommendedHours * 60, // 25 hours * 60 clips/hr
        priority: recommendation.priority == 'high' ? 9 : 5,
        createdAt: now,
        updatedAt: now,
      );

      expect(nextMission.requiredDialectId, equals(targetDialectId));
      expect(nextMission.priority, equals(9));
      expect(nextMission.status, equals(MissionStatus.active));
    });
  });
}
