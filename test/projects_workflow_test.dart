import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/models/gsip_models.dart';
import 'package:gujarati_dialect_curator/services/dataset_builder_service.dart';

void main() {
  group('ProjectsWorkflow - Data Requirements & Deficit Analysis', () {
    final now = DateTime.now();

    final approvedAssets = [
      // 1 hour of Kathiyawadi Healthcare data (4 clips * 900,000 ms = 3600s = 1 hr)
      DataAsset(
        id: 'kh-1',
        reviewStatus: ReviewStatus.approved,
        dialectId: 2,
        domainId: 'healthcare',
        contributorId: 'speaker-1',
        durationMs: 900000,
        qualityScore: 85,
        consentTypeId: 'commercial_ai',
        createdAt: now,
        updatedAt: now,
      ),
      DataAsset(
        id: 'kh-2',
        reviewStatus: ReviewStatus.approved,
        dialectId: 2,
        domainId: 'healthcare',
        contributorId: 'speaker-2',
        durationMs: 900000,
        qualityScore: 90,
        consentTypeId: 'commercial_ai',
        createdAt: now,
        updatedAt: now,
      ),
      DataAsset(
        id: 'kh-3',
        reviewStatus: ReviewStatus.approved,
        dialectId: 2,
        domainId: 'healthcare',
        contributorId: 'speaker-3',
        durationMs: 900000,
        qualityScore: 92,
        consentTypeId: 'commercial_ai',
        createdAt: now,
        updatedAt: now,
      ),
      DataAsset(
        id: 'kh-4',
        reviewStatus: ReviewStatus.approved,
        dialectId: 2,
        domainId: 'healthcare',
        contributorId: 'speaker-4',
        durationMs: 900000,
        qualityScore: 88,
        consentTypeId: 'commercial_ai',
        createdAt: now,
        updatedAt: now,
      ),
      // Surti General data (1 hour)
      DataAsset(
        id: 'sg-1',
        reviewStatus: ReviewStatus.approved,
        dialectId: 3,
        domainId: 'general',
        contributorId: 'speaker-5',
        durationMs: 3600000,
        qualityScore: 95,
        consentTypeId: 'commercial_ai',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    test('Data Deficit Analysis: Accurately identifies hours deficit against project target', () {
      const targetHours = 5.0;

      final eval = DatasetBuilderService.evaluateAssets(
        allAssets: approvedAssets,
        criteria: const DatasetFilterCriteria(
          domainIds: ['healthcare'],
          dialectIds: [2],
          minQualityScore: 80,
          requiredConsentType: 'commercial_ai',
        ),
      );

      final existingHours = eval.totalDurationMs / (1000.0 * 3600.0);
      final missingHours = (targetHours - existingHours).clamp(0.0, targetHours);
      final progressFraction = (existingHours / targetHours).clamp(0.0, 1.0);

      expect(existingHours, closeTo(1.0, 0.01));
      expect(missingHours, closeTo(4.0, 0.01));
      expect(progressFraction, closeTo(0.2, 0.01));
      expect(eval.eligibleAssets.length, equals(4));
    });

    test('Mission Generation from Deficit: Computes correct quantity of clips needed', () {
      const missingHours = 4.0;
      const averageClipDurationSeconds = 15.0;

      // clips needed = (missingHours * 3600) / averageClipDurationSeconds
      final neededClips = ((missingHours * 3600) / averageClipDurationSeconds).round().clamp(10, 500);

      expect(neededClips, equals(500)); // clamped to 500 max per single mission

      final mission = Mission(
        id: 'gen-mission-1',
        title: 'Project Deficit: Kathiyawadi Healthcare Collection',
        description: 'Auto-generated mission to fulfill 4.0 hour deficit',
        taskType: MissionTaskType.recording,
        status: MissionStatus.active,
        requiredDialectId: 2,
        requiredDomainId: 'healthcare',
        targetQuantity: neededClips,
        priority: 9,
        tags: const ['project-requirement', 'healthcare', 'kathiyawadi'],
        createdAt: now,
        updatedAt: now,
      );

      expect(mission.requiredDialectId, equals(2));
      expect(mission.requiredDomainId, equals('healthcare'));
      expect(mission.targetQuantity, equals(500));
      expect(mission.priority, equals(9));
      expect(mission.status, equals(MissionStatus.active));
    });
  });
}
