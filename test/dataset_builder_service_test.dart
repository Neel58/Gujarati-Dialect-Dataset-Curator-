import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/models/gsip_models.dart';
import 'package:gujarati_dialect_curator/services/dataset_builder_service.dart';

void main() {
  group('DatasetBuilderService - Filtering, Consent Enforcement & Statistics', () {
    final now = DateTime.now();

    final testAssets = [
      // 1: Approved, Kathiyawadi, commercial_ai, quality 90
      DataAsset(
        id: 'asset-1',
        reviewStatus: ReviewStatus.approved,
        dialectId: 2,
        domainId: 'healthcare',
        contributorId: 'speaker-A',
        durationMs: 15000,
        qualityScore: 90,
        consentTypeId: 'commercial_ai',
        createdAt: now,
        updatedAt: now,
      ),
      // 2: Approved, Kathiyawadi, research_only, quality 85
      DataAsset(
        id: 'asset-2',
        reviewStatus: ReviewStatus.approved,
        dialectId: 2,
        domainId: 'healthcare',
        contributorId: 'speaker-B',
        durationMs: 20000,
        qualityScore: 85,
        consentTypeId: 'research_only',
        createdAt: now,
        updatedAt: now,
      ),
      // 3: Pending review (must be excluded from any dataset)
      DataAsset(
        id: 'asset-3',
        reviewStatus: ReviewStatus.pending,
        dialectId: 2,
        domainId: 'healthcare',
        contributorId: 'speaker-C',
        durationMs: 25000,
        qualityScore: 95,
        consentTypeId: 'commercial_ai',
        createdAt: now,
        updatedAt: now,
      ),
      // 4: Approved, Surti, open consent, quality 80
      DataAsset(
        id: 'asset-4',
        reviewStatus: ReviewStatus.approved,
        dialectId: 3,
        domainId: 'agriculture',
        contributorId: 'speaker-A', // same speaker
        durationMs: 10000,
        qualityScore: 80,
        consentTypeId: 'open',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    test('Excludes pending review assets from dataset selection', () {
      const criteria = DatasetFilterCriteria();
      final eval = DatasetBuilderService.evaluateAssets(
        allAssets: testAssets,
        criteria: criteria,
      );

      expect(eval.eligibleAssets.any((a) => a.id == 'asset-3'), isFalse);
      expect(eval.excludedAssets.any((a) => a.id == 'asset-3'), isTrue);
    });

    test('Enforces commercial consent boundary: research_only excluded for commercial_ai dataset', () {
      const criteria = DatasetFilterCriteria(
        requiredConsentType: 'commercial_ai',
      );
      final eval = DatasetBuilderService.evaluateAssets(
        allAssets: testAssets,
        criteria: criteria,
      );

      // asset-1 (commercial_ai) and asset-4 (open) should be eligible
      // asset-2 (research_only) must be excluded
      expect(eval.eligibleAssets.map((a) => a.id), containsAll(['asset-1', 'asset-4']));
      expect(eval.eligibleAssets.any((a) => a.id == 'asset-2'), isFalse);
      expect(eval.excludedAssets.any((a) => a.id == 'asset-2'), isTrue);
    });

    test('Computes exact statistics on eligible assets', () {
      const criteria = DatasetFilterCriteria(
        dialectIds: [2], // Kathiyawadi only
      );
      final eval = DatasetBuilderService.evaluateAssets(
        allAssets: testAssets,
        criteria: criteria,
      );

      // asset-1 (15s, q:90) and asset-2 (20s, q:85) are Kathiyawadi & approved
      expect(eval.eligibleAssets.length, equals(2));
      expect(eval.totalDurationMs, equals(35000));
      expect(eval.uniqueSpeakers, equals(2));
      expect(eval.averageQualityScore, equals(87.5));
      expect(eval.dialectDistribution['2'], equals(2));
      expect(eval.domainDistribution['healthcare'], equals(2));
    });

    test('Suggests correct next version string', () {
      expect(DatasetBuilderService.suggestNextVersion([]), equals('1.0'));
      expect(DatasetBuilderService.suggestNextVersion(['1.0']), equals('1.1'));
      expect(DatasetBuilderService.suggestNextVersion(['1.0', '1.1']), equals('1.2'));
    });
  });
}
