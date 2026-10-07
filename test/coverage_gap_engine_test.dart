import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/models/gsip_models.dart';
import 'package:gujarati_dialect_curator/services/coverage_gap_engine.dart';

void main() {
  group('CoverageGapEngine - Corpus Coverage & Actionable Gaps', () {
    test('Empty corpus identifies high-priority dialect gaps', () {
      final report = CoverageGapEngine.analyze([]);

      expect(report.totalAssets, equals(0));
      expect(report.totalHours, equals(0.0));
      expect(report.detectedGaps.isNotEmpty, isTrue);
      expect(report.detectedGaps.any((g) => g.priority == 'high'), isTrue);
    });

    test('Accurately aggregates hours and detects deficit in under-represented dialect', () {
      final now = DateTime.now();

      // Create dummy assets:
      // Surti: 120 recordings of 30s each = 3600s = 1.0 hour
      final surtiAssets = List.generate(
        120,
        (i) => DataAsset(
          id: 'surti-$i',
          dialectId: 3, // Surti
          domainId: 'general',
          contributorId: 'contributor-${i % 5}',
          durationMs: 30000,
          qualityScore: 90,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Charotari: 10 recordings of 30s each = 300s = 0.083 hours
      final charotariAssets = List.generate(
        10,
        (i) => DataAsset(
          id: 'charotari-$i',
          dialectId: 4, // Charotari
          domainId: 'healthcare',
          contributorId: 'contributor-99',
          speakerAgeBand: '65+',
          durationMs: 30000,
          qualityScore: 85,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final report = CoverageGapEngine.analyze([...surtiAssets, ...charotariAssets]);

      expect(report.totalAssets, equals(130));
      // Total hours: (120 * 30 + 10 * 30) = 3900s = 1.0833 hrs
      expect(report.totalHours, closeTo(1.0833, 0.01));

      // Dialect slices
      final surtiSlice = report.dialectCoverage['3'];
      expect(surtiSlice, isNotNull);
      expect(surtiSlice!.assetCount, equals(120));
      expect(surtiSlice.totalHours, closeTo(1.0, 0.01));
      expect(surtiSlice.uniqueSpeakers, equals(5));

      final charotariSlice = report.dialectCoverage['4'];
      expect(charotariSlice, isNotNull);
      expect(charotariSlice!.assetCount, equals(10));
      expect(charotariSlice.totalHours, closeTo(0.0833, 0.01));

      // Charotari has target 10h, only ~0.08h -> ratio < 0.3 -> HIGH PRIORITY GAP
      final charotariGap = report.detectedGaps.firstWhere(
        (g) => g.dialectId == 4,
      );
      expect(charotariGap.priority, equals('high'));
      expect(charotariGap.deficitHours, greaterThan(9.0));

      // Test converting gap to mission proposal
      final proposal = charotariGap.toMissionProposal();
      expect(proposal.requiredDialectId, equals(4));
      expect(proposal.taskType, equals(MissionTaskType.recording));
      expect(proposal.priority, equals(9));
      expect(proposal.targetQuantity, greaterThanOrEqualTo(10));
    });
  });
}
