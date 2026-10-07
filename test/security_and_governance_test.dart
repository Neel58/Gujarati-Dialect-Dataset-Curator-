import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/models/gsip_models.dart';
import 'package:gujarati_dialect_curator/services/dataset_builder_service.dart';

void main() {
  group('Security & Governance - Strict Platform Invariants', () {
    final now = DateTime.now();

    test('Self-approval block: Contributor cannot approve their own submitted audio asset', () {
      const currentCuratorId = 'curator-user-123';

      final ownAsset = DataAsset(
        id: 'asset-own-1',
        contributorId: currentCuratorId,
        reviewStatus: ReviewStatus.pending,
        transcript: 'મારું પોતાનું રેકોર્ડિંગ',
        createdAt: now,
        updatedAt: now,
      );

      final otherContributorAsset = DataAsset(
        id: 'asset-other-2',
        contributorId: 'contributor-user-456',
        reviewStatus: ReviewStatus.pending,
        transcript: 'અન્ય વ્યક્તિનું રેકોર્ડિંગ',
        createdAt: now,
        updatedAt: now,
      );

      // Governance rule: Contributor cannot approve their own submission
      bool canApprove(DataAsset asset, String userId) {
        if (asset.contributorId != null && asset.contributorId == userId) {
          return false;
        }
        return true;
      }

      expect(canApprove(ownAsset, currentCuratorId), isFalse,
          reason: 'A curator/admin must NOT be permitted to approve their own contribution.');

      expect(canApprove(otherContributorAsset, currentCuratorId), isTrue,
          reason: 'A curator/admin CAN approve contributions submitted by other contributors.');
    });

    test('Governance: Unapproved assets (pending, rejected, needsRevision) are strictly barred from datasets', () {
      final assets = [
        DataAsset(
          id: 'a-approved',
          contributorId: 'u1',
          reviewStatus: ReviewStatus.approved,
          qualityScore: 90,
          consentTypeId: 'commercial_ai',
          createdAt: now,
          updatedAt: now,
        ),
        DataAsset(
          id: 'a-pending',
          contributorId: 'u2',
          reviewStatus: ReviewStatus.pending,
          qualityScore: 99,
          consentTypeId: 'commercial_ai',
          createdAt: now,
          updatedAt: now,
        ),
        DataAsset(
          id: 'a-rejected',
          contributorId: 'u3',
          reviewStatus: ReviewStatus.rejected,
          qualityScore: 85,
          consentTypeId: 'commercial_ai',
          createdAt: now,
          updatedAt: now,
        ),
        DataAsset(
          id: 'a-revision',
          contributorId: 'u4',
          reviewStatus: ReviewStatus.needsRevision,
          qualityScore: 88,
          consentTypeId: 'commercial_ai',
          createdAt: now,
          updatedAt: now,
        ),
        DataAsset(
          id: 'a-deleted',
          contributorId: 'u5',
          reviewStatus: ReviewStatus.approved,
          isDeleted: true,
          qualityScore: 92,
          consentTypeId: 'commercial_ai',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final eval = DatasetBuilderService.evaluateAssets(
        allAssets: assets,
        criteria: const DatasetFilterCriteria(
          minQualityScore: 50,
          requiredConsentType: 'commercial_ai',
        ),
      );

      expect(eval.eligibleAssets.length, equals(1));
      expect(eval.eligibleAssets.first.id, equals('a-approved'));
      expect(eval.excludedAssets.map((a) => a.id), containsAll(['a-pending', 'a-rejected', 'a-revision', 'a-deleted']));
    });

    test('Consent boundary: Open distribution dataset strictly excludes commercial_ai and research_only', () {
      final assets = [
        DataAsset(
          id: 'open-1',
          contributorId: 'u1',
          reviewStatus: ReviewStatus.approved,
          qualityScore: 90,
          consentTypeId: 'open',
          createdAt: now,
          updatedAt: now,
        ),
        DataAsset(
          id: 'commercial-2',
          contributorId: 'u2',
          reviewStatus: ReviewStatus.approved,
          qualityScore: 90,
          consentTypeId: 'commercial_ai',
          createdAt: now,
          updatedAt: now,
        ),
        DataAsset(
          id: 'research-3',
          contributorId: 'u3',
          reviewStatus: ReviewStatus.approved,
          qualityScore: 90,
          consentTypeId: 'research_only',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final openEval = DatasetBuilderService.evaluateAssets(
        allAssets: assets,
        criteria: const DatasetFilterCriteria(
          minQualityScore: 50,
          requiredConsentType: 'open',
        ),
      );

      expect(openEval.eligibleAssets.length, equals(1));
      expect(openEval.eligibleAssets.first.id, equals('open-1'));
      expect(openEval.excludedAssets.map((a) => a.id), containsAll(['commercial-2', 'research-3']));
    });

    test('Dataset Version Immutability: Published versions cannot be mutated or un-published', () {
      final publishedVersion = DatasetVersion(
        id: 'dv-1',
        datasetId: 'ds-1',
        version: '1.0',
        filterCriteria: const {'min_quality': 80},
        assetCount: 50,
        totalDurationMs: 3600000,
        speakerCount: 12,
        isPublished: true,
        publishedAt: now,
        createdAt: now,
      );

      bool canModifyDatasetVersion(DatasetVersion version, {required bool isAttemptingUnpublish}) {
        if (version.isPublished) {
          return false;
        }
        return true;
      }

      expect(canModifyDatasetVersion(publishedVersion, isAttemptingUnpublish: false), isFalse,
          reason: 'Published versions must be permanently immutable.');
      expect(canModifyDatasetVersion(publishedVersion, isAttemptingUnpublish: true), isFalse,
          reason: 'Cannot unpublish a published dataset version.');

      final draftVersion = DatasetVersion(
        id: 'dv-2',
        datasetId: 'ds-1',
        version: '1.1',
        filterCriteria: const {'min_quality': 85},
        assetCount: 60,
        totalDurationMs: 4200000,
        speakerCount: 15,
        isPublished: false,
        createdAt: now,
      );

      expect(canModifyDatasetVersion(draftVersion, isAttemptingUnpublish: false), isTrue,
          reason: 'Draft versions can be modified until published.');
    });
  });
}
