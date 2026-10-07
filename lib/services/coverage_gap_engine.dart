import '../models/gsip_models.dart';

/// Aggregated breakdown for a specific category slice.
class SliceCoverage {
  final String key;
  final String label;
  final int assetCount;
  final int totalDurationMs;
  final double totalHours;
  final double averageQuality;
  final int uniqueSpeakers;

  const SliceCoverage({
    required this.key,
    required this.label,
    required this.assetCount,
    required this.totalDurationMs,
    required this.totalHours,
    required this.averageQuality,
    required this.uniqueSpeakers,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'asset_count': assetCount,
        'total_duration_ms': totalDurationMs,
        'total_hours': totalHours,
        'average_quality': averageQuality,
        'unique_speakers': uniqueSpeakers,
      };
}

/// An identified data coverage gap with actionable targets.
class CoverageGap {
  final String id;
  final String title;
  final String description;
  final String priority; // 'high', 'medium', 'low'
  final String dimension; // 'dialect', 'domain', 'environment', 'age_band'
  final String dimensionValue;
  final int? dialectId;
  final String? domainId;
  final String? environmentId;
  final String? ageBand;
  final double currentHours;
  final double targetHours;
  final double deficitHours;
  final double coverageRatio; // current / target

  const CoverageGap({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.dimension,
    required this.dimensionValue,
    this.dialectId,
    this.domainId,
    this.environmentId,
    this.ageBand,
    required this.currentHours,
    required this.targetHours,
    required this.deficitHours,
    required this.coverageRatio,
  });

  /// Generate a ready-to-create mission proposal directly addressing this gap.
  MissionProposal toMissionProposal() {
    final neededHours = deficitHours > 0 ? deficitHours : 2.0;
    // Assume average 15 seconds per utterance = ~240 recordings per hour
    final targetRecordings = (neededHours * 240).round().clamp(10, 500);

    return MissionProposal(
      title: 'Targeted Collection: $title',
      description:
          'Data gap detected: Currently $currentHours hrs vs $targetHours hrs target. '
          '$description',
      taskType: MissionTaskType.recording,
      requiredDialectId: dialectId,
      requiredDomainId: domainId,
      requiredEnvironmentId: environmentId,
      requiredAgeBand: ageBand,
      targetQuantity: targetRecordings,
      qualityThreshold: 80,
      priority: priority == 'high' ? 9 : (priority == 'medium' ? 6 : 3),
      tags: [dimension, dimensionValue, 'gap-resolution'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority,
        'dimension': dimension,
        'dimension_value': dimensionValue,
        'current_hours': currentHours,
        'target_hours': targetHours,
        'deficit_hours': deficitHours,
        'coverage_ratio': coverageRatio,
      };
}

/// A structured proposal for creating a mission from a gap or recommendation.
class MissionProposal {
  final String title;
  final String description;
  final MissionTaskType taskType;
  final int? requiredDialectId;
  final String? requiredDomainId;
  final String? requiredEnvironmentId;
  final String? requiredAgeBand;
  final int targetQuantity;
  final int qualityThreshold;
  final int priority;
  final List<String> tags;

  const MissionProposal({
    required this.title,
    required this.description,
    required this.taskType,
    this.requiredDialectId,
    this.requiredDomainId,
    this.requiredEnvironmentId,
    this.requiredAgeBand,
    required this.targetQuantity,
    required this.qualityThreshold,
    required this.priority,
    required this.tags,
  });
}

/// Complete corpus coverage analysis report.
class CorpusCoverageReport {
  final int totalAssets;
  final double totalHours;
  final int totalUniqueContributors;
  final double overallAverageQuality;
  final Map<String, SliceCoverage> dialectCoverage;
  final Map<String, SliceCoverage> domainCoverage;
  final Map<String, SliceCoverage> environmentCoverage;
  final Map<String, SliceCoverage> ageBandCoverage;
  final List<CoverageGap> detectedGaps;

  const CorpusCoverageReport({
    required this.totalAssets,
    required this.totalHours,
    required this.totalUniqueContributors,
    required this.overallAverageQuality,
    required this.dialectCoverage,
    required this.domainCoverage,
    required this.environmentCoverage,
    required this.ageBandCoverage,
    required this.detectedGaps,
  });

  Map<String, dynamic> toJson() => {
        'total_assets': totalAssets,
        'total_hours': totalHours,
        'total_contributors': totalUniqueContributors,
        'overall_average_quality': overallAverageQuality,
        'dialect_coverage':
            dialectCoverage.map((k, v) => MapEntry(k, v.toJson())),
        'domain_coverage':
            domainCoverage.map((k, v) => MapEntry(k, v.toJson())),
        'environment_coverage':
            environmentCoverage.map((k, v) => MapEntry(k, v.toJson())),
        'age_band_coverage':
            ageBandCoverage.map((k, v) => MapEntry(k, v.toJson())),
        'detected_gaps': detectedGaps.map((g) => g.toJson()).toList(),
      };
}

/// Target threshold configuration for coverage calculations.
class CoverageTargets {
  final double defaultDialectTargetHours;
  final double defaultDomainTargetHours;
  final double defaultEnvironmentTargetHours;
  final double defaultAgeBandTargetHours;

  const CoverageTargets({
    this.defaultDialectTargetHours = 10.0,
    this.defaultDomainTargetHours = 5.0,
    this.defaultEnvironmentTargetHours = 3.0,
    this.defaultAgeBandTargetHours = 5.0,
  });
}

/// CoverageGapEngine calculates comprehensive corpus coverage distributions
/// and generates actionable gaps and mission proposals from real DataAsset rows.
class CoverageGapEngine {
  /// Known dialects mapping for labels if not provided.
  static const Map<int, String> knownDialectNames = {
    1: 'Standard Gujarati',
    2: 'Kathiyawadi',
    3: 'Surti',
    4: 'Charotari',
    5: 'Pattani (North Gujarat)',
    6: 'Other',
  };

  /// Known domain names for labels.
  static const Map<String, String> knownDomainNames = {
    'general': 'General Conversation',
    'healthcare': 'Healthcare & Medicine',
    'agriculture': 'Agriculture & Farming',
    'education': 'Education',
    'commerce': 'Commerce & Trade',
    'government': 'Government & Civic',
    'religious': 'Religious & Devotional',
    'news': 'News & Media',
    'narrative': 'Storytelling & Folklore',
  };

  /// Compute coverage report and gap recommendations from actual data assets.
  static CorpusCoverageReport analyze(
    List<DataAsset> assets, {
    CoverageTargets targets = const CoverageTargets(),
    Map<int, String>? dialectLabels,
  }) {
    final dialects = dialectLabels ?? knownDialectNames;

    if (assets.isEmpty) {
      // If corpus is empty, generate initial bootstrap gaps
      final initialGaps = <CoverageGap>[];
      for (final entry in dialects.entries) {
        if (entry.key == 6) continue; // skip 'other'
        initialGaps.add(CoverageGap(
          id: 'gap-dialect-${entry.key}',
          title: '${entry.value} Dialect Data Needed',
          description:
              'No approved audio recordings currently exist for ${entry.value}.',
          priority: 'high',
          dimension: 'dialect',
          dimensionValue: entry.value,
          dialectId: entry.key,
          currentHours: 0.0,
          targetHours: targets.defaultDialectTargetHours,
          deficitHours: targets.defaultDialectTargetHours,
          coverageRatio: 0.0,
        ));
      }

      return CorpusCoverageReport(
        totalAssets: 0,
        totalHours: 0.0,
        totalUniqueContributors: 0,
        overallAverageQuality: 0.0,
        dialectCoverage: {},
        domainCoverage: {},
        environmentCoverage: {},
        ageBandCoverage: {},
        detectedGaps: initialGaps,
      );
    }

    int totalDurationMs = 0;
    int totalQualityScoreSum = 0;
    int qualityScoreCount = 0;
    final uniqueContributors = <String>{};

    // Buckets
    final dialectBuckets = <int, List<DataAsset>>{};
    final domainBuckets = <String, List<DataAsset>>{};
    final environmentBuckets = <String, List<DataAsset>>{};
    final ageBandBuckets = <String, List<DataAsset>>{};

    for (final a in assets) {
      final dur = a.durationMs ?? 0;
      totalDurationMs += dur;

      if (a.qualityScore != null) {
        totalQualityScoreSum += a.qualityScore!;
        qualityScoreCount++;
      }

      if (a.contributorId != null) {
        uniqueContributors.add(a.contributorId!);
      }

      if (a.dialectId != null) {
        dialectBuckets.putIfAbsent(a.dialectId!, () => []).add(a);
      }

      domainBuckets.putIfAbsent(a.domainId, () => []).add(a);

      if (a.environmentId != null) {
        environmentBuckets.putIfAbsent(a.environmentId!, () => []).add(a);
      }

      if (a.speakerAgeBand != null) {
        ageBandBuckets.putIfAbsent(a.speakerAgeBand!, () => []).add(a);
      }
    }

    final double totalHours = totalDurationMs / (1000.0 * 3600.0);
    final double overallAvgQuality = qualityScoreCount > 0
        ? (totalQualityScoreSum / qualityScoreCount)
        : 0.0;

    // Build slices
    final dialectCoverage = <String, SliceCoverage>{};
    for (final entry in dialects.entries) {
      final dId = entry.key;
      final label = entry.value;
      final list = dialectBuckets[dId] ?? [];
      dialectCoverage[dId.toString()] = _buildSlice(dId.toString(), label, list);
    }

    final domainCoverage = <String, SliceCoverage>{};
    for (final entry in knownDomainNames.entries) {
      final domId = entry.key;
      final label = entry.value;
      final list = domainBuckets[domId] ?? [];
      domainCoverage[domId] = _buildSlice(domId, label, list);
    }

    final environmentCoverage = <String, SliceCoverage>{};
    for (final entry in environmentBuckets.entries) {
      final envId = entry.key;
      final list = entry.value;
      environmentCoverage[envId] = _buildSlice(envId, envId, list);
    }

    final ageBandCoverage = <String, SliceCoverage>{};
    for (final band in ['18-25', '26-35', '36-50', '51-65', '65+']) {
      final list = ageBandBuckets[band] ?? [];
      ageBandCoverage[band] = _buildSlice(band, band, list);
    }

    // Detect Gaps
    final gaps = <CoverageGap>[];

    // 1. Dialect gaps
    for (final entry in dialects.entries) {
      final dId = entry.key;
      final dName = entry.value;
      if (dId == 6) continue; // skip other

      final slice = dialectCoverage[dId.toString()]!;
      final target = targets.defaultDialectTargetHours;
      if (slice.totalHours < target) {
        final deficit = target - slice.totalHours;
        final ratio = target > 0 ? (slice.totalHours / target) : 1.0;
        final priority = ratio < 0.3 ? 'high' : (ratio < 0.7 ? 'medium' : 'low');

        gaps.add(CoverageGap(
          id: 'gap-dialect-$dId',
          title: '$dName Under-Represented',
          description:
              'Current coverage is ${slice.totalHours.toStringAsFixed(1)}h '
              '(${slice.assetCount} recordings) vs target of ${target.toStringAsFixed(0)}h.',
          priority: priority,
          dimension: 'dialect',
          dimensionValue: dName,
          dialectId: dId,
          currentHours: slice.totalHours,
          targetHours: target,
          deficitHours: deficit,
          coverageRatio: ratio,
        ));
      }
    }

    // 2. High-value domain gaps (e.g. Healthcare, Agriculture)
    for (final dKey in ['healthcare', 'agriculture', 'education']) {
      final slice = domainCoverage[dKey];
      final target = targets.defaultDomainTargetHours;
      if (slice != null && slice.totalHours < target) {
        final deficit = target - slice.totalHours;
        final ratio = target > 0 ? (slice.totalHours / target) : 1.0;
        final priority = ratio < 0.3 ? 'high' : 'medium';

        gaps.add(CoverageGap(
          id: 'gap-domain-$dKey',
          title: '${slice.label} Data Deficit',
          description:
              'Specialized vocabulary requires coverage. '
              'Currently ${slice.totalHours.toStringAsFixed(1)}h vs target ${target.toStringAsFixed(0)}h.',
          priority: priority,
          dimension: 'domain',
          dimensionValue: slice.label,
          domainId: dKey,
          currentHours: slice.totalHours,
          targetHours: target,
          deficitHours: deficit,
          coverageRatio: ratio,
        ));
      }
    }

    // 3. Senior speaker age band gap (51-65, 65+)
    for (final band in ['51-65', '65+']) {
      final slice = ageBandCoverage[band];
      final target = targets.defaultAgeBandTargetHours;
      if (slice != null && slice.totalHours < target) {
        final deficit = target - slice.totalHours;
        final ratio = target > 0 ? (slice.totalHours / target) : 1.0;

        if (ratio < 0.5) {
          gaps.add(CoverageGap(
            id: 'gap-age-$band',
            title: 'Senior Speakers ($band) Under-Represented',
            description:
                'Only ${slice.totalHours.toStringAsFixed(1)}h recorded from $band age group. '
                'Senior acoustic models require broader demographic balance.',
            priority: ratio < 0.2 ? 'high' : 'medium',
            dimension: 'age_band',
            dimensionValue: band,
            ageBand: band,
            currentHours: slice.totalHours,
            targetHours: target,
            deficitHours: deficit,
            coverageRatio: ratio,
          ));
        }
      }
    }

    // Sort gaps: high priority first, then lowest coverage ratio
    gaps.sort((a, b) {
      final pA = a.priority == 'high' ? 0 : (a.priority == 'medium' ? 1 : 2);
      final pB = b.priority == 'high' ? 0 : (b.priority == 'medium' ? 1 : 2);
      if (pA != pB) return pA.compareTo(pB);
      return a.coverageRatio.compareTo(b.coverageRatio);
    });

    return CorpusCoverageReport(
      totalAssets: assets.length,
      totalHours: totalHours,
      totalUniqueContributors: uniqueContributors.length,
      overallAverageQuality: overallAvgQuality,
      dialectCoverage: dialectCoverage,
      domainCoverage: domainCoverage,
      environmentCoverage: environmentCoverage,
      ageBandCoverage: ageBandCoverage,
      detectedGaps: gaps,
    );
  }

  static SliceCoverage _buildSlice(
      String key, String label, List<DataAsset> items) {
    int durMs = 0;
    int qSum = 0;
    int qCount = 0;
    final speakers = <String>{};

    for (final it in items) {
      durMs += it.durationMs ?? 0;
      if (it.qualityScore != null) {
        qSum += it.qualityScore!;
        qCount++;
      }
      if (it.contributorId != null) {
        speakers.add(it.contributorId!);
      }
    }

    return SliceCoverage(
      key: key,
      label: label,
      assetCount: items.length,
      totalDurationMs: durMs,
      totalHours: durMs / (1000.0 * 3600.0),
      averageQuality: qCount > 0 ? (qSum / qCount) : 0.0,
      uniqueSpeakers: speakers.length,
    );
  }
}
