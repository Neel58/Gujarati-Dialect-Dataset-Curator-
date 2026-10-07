import '../models/gsip_models.dart';

/// Filter criteria specified when creating a dataset or dataset version.
class DatasetFilterCriteria {
  final List<int>? dialectIds;
  final List<String>? domainIds;
  final List<String>? environmentIds;
  final int? minQualityScore;
  final String? requiredConsentType; // e.g. 'commercial_ai', 'open', 'research_only'
  final int? minDurationMs;
  final int? maxDurationMs;

  const DatasetFilterCriteria({
    this.dialectIds,
    this.domainIds,
    this.environmentIds,
    this.minQualityScore,
    this.requiredConsentType,
    this.minDurationMs,
    this.maxDurationMs,
  });

  Map<String, dynamic> toJson() => {
        if (dialectIds != null) 'dialect_ids': dialectIds,
        if (domainIds != null) 'domain_ids': domainIds,
        if (environmentIds != null) 'environment_ids': environmentIds,
        if (minQualityScore != null) 'min_quality_score': minQualityScore,
        if (requiredConsentType != null)
          'required_consent_type': requiredConsentType,
        if (minDurationMs != null) 'min_duration_ms': minDurationMs,
        if (maxDurationMs != null) 'max_duration_ms': maxDurationMs,
      };

  factory DatasetFilterCriteria.fromJson(Map<String, dynamic> json) =>
      DatasetFilterCriteria(
        dialectIds: (json['dialect_ids'] as List<dynamic>?)?.cast<int>(),
        domainIds: (json['domain_ids'] as List<dynamic>?)?.cast<String>(),
        environmentIds:
            (json['environment_ids'] as List<dynamic>?)?.cast<String>(),
        minQualityScore: json['min_quality_score'] as int?,
        requiredConsentType: json['required_consent_type'] as String?,
        minDurationMs: json['min_duration_ms'] as int?,
        maxDurationMs: json['max_duration_ms'] as int?,
      );
}

/// Result of evaluating candidate assets against filter criteria.
class DatasetBuildEvaluation {
  final List<DataAsset> eligibleAssets;
  final List<DataAsset> excludedAssets;
  final Map<String, int> exclusionReasons;
  final int totalDurationMs;
  final int uniqueSpeakers;
  final Map<String, int> dialectDistribution;
  final Map<String, int> domainDistribution;
  final double averageQualityScore;
  final Map<String, int> consentDistribution;

  const DatasetBuildEvaluation({
    required this.eligibleAssets,
    required this.excludedAssets,
    required this.exclusionReasons,
    required this.totalDurationMs,
    required this.uniqueSpeakers,
    required this.dialectDistribution,
    required this.domainDistribution,
    required this.averageQualityScore,
    required this.consentDistribution,
  });
}

/// Service handling dataset creation, version statistics, and consent boundaries.
class DatasetBuilderService {
  /// Filters candidate assets against criteria and enforces consent & review requirements.
  static DatasetBuildEvaluation evaluateAssets({
    required List<DataAsset> allAssets,
    required DatasetFilterCriteria criteria,
  }) {
    final eligible = <DataAsset>[];
    final excluded = <DataAsset>[];
    final exclusionReasons = <String, int>{};

    void recordExclusion(DataAsset asset, String reason) {
      excluded.add(asset);
      exclusionReasons[reason] = (exclusionReasons[reason] ?? 0) + 1;
    }

    for (final a in allAssets) {
      // 1. Mandatory: only approved, non-deleted assets can enter datasets
      if (a.reviewStatus != ReviewStatus.approved) {
        recordExclusion(a, 'Not approved (status: ${a.reviewStatus.value})');
        continue;
      }
      if (a.isDeleted) {
        recordExclusion(a, 'Deleted');
        continue;
      }

      // 2. Consent scope enforcement
      // If dataset specifies commercial_ai, research_only assets CANNOT be included.
      if (criteria.requiredConsentType == 'commercial_ai') {
        if (a.consentTypeId != 'commercial_ai' && a.consentTypeId != 'open') {
          recordExclusion(a, 'Consent scope insufficient for commercial dataset');
          continue;
        }
      } else if (criteria.requiredConsentType == 'open') {
        if (a.consentTypeId != 'open') {
          recordExclusion(a, 'Consent scope insufficient for open distribution');
          continue;
        }
      }

      // 3. Dialect filter
      if (criteria.dialectIds != null && criteria.dialectIds!.isNotEmpty) {
        if (a.dialectId == null || !criteria.dialectIds!.contains(a.dialectId)) {
          recordExclusion(a, 'Dialect not matching');
          continue;
        }
      }

      // 4. Domain filter
      if (criteria.domainIds != null && criteria.domainIds!.isNotEmpty) {
        if (!criteria.domainIds!.contains(a.domainId)) {
          recordExclusion(a, 'Domain not matching');
          continue;
        }
      }

      // 5. Environment filter
      if (criteria.environmentIds != null &&
          criteria.environmentIds!.isNotEmpty) {
        if (a.environmentId == null ||
            !criteria.environmentIds!.contains(a.environmentId)) {
          recordExclusion(a, 'Environment not matching');
          continue;
        }
      }

      // 6. Quality threshold
      if (criteria.minQualityScore != null) {
        if (a.qualityScore == null || a.qualityScore! < criteria.minQualityScore!) {
          recordExclusion(a, 'Quality score below threshold (${criteria.minQualityScore})');
          continue;
        }
      }

      // 7. Duration limits
      if (criteria.minDurationMs != null) {
        if ((a.durationMs ?? 0) < criteria.minDurationMs!) {
          recordExclusion(a, 'Duration below minimum (${criteria.minDurationMs}ms)');
          continue;
        }
      }
      if (criteria.maxDurationMs != null) {
        if ((a.durationMs ?? 0) > criteria.maxDurationMs!) {
          recordExclusion(a, 'Duration exceeds maximum (${criteria.maxDurationMs}ms)');
          continue;
        }
      }

      eligible.add(a);
    }

    // Compute statistics on eligible assets
    int totalDurationMs = 0;
    int qualitySum = 0;
    int qualityCount = 0;
    final speakers = <String>{};
    final dialectDist = <String, int>{};
    final domainDist = <String, int>{};
    final consentDist = <String, int>{};

    for (final a in eligible) {
      totalDurationMs += a.durationMs ?? 0;
      if (a.qualityScore != null) {
        qualitySum += a.qualityScore!;
        qualityCount++;
      }
      if (a.contributorId != null) {
        speakers.add(a.contributorId!);
      }

      final dKey = a.dialectId?.toString() ?? 'unknown';
      dialectDist[dKey] = (dialectDist[dKey] ?? 0) + 1;

      final domKey = a.domainId;
      domainDist[domKey] = (domainDist[domKey] ?? 0) + 1;

      final cKey = a.consentTypeId;
      consentDist[cKey] = (consentDist[cKey] ?? 0) + 1;
    }

    return DatasetBuildEvaluation(
      eligibleAssets: eligible,
      excludedAssets: excluded,
      exclusionReasons: exclusionReasons,
      totalDurationMs: totalDurationMs,
      uniqueSpeakers: speakers.length,
      dialectDistribution: dialectDist,
      domainDistribution: domainDist,
      averageQualityScore:
          qualityCount > 0 ? (qualitySum / qualityCount).toDouble() : 0.0,
      consentDistribution: consentDist,
    );
  }

  /// Suggest next version name based on existing versions.
  /// e.g. [] -> '1.0', ['1.0'] -> '1.1'
  static String suggestNextVersion(List<String> existingVersions) {
    if (existingVersions.isEmpty) return '1.0';

    final parsedVersions = <({int major, int minor})>[];
    for (final v in existingVersions) {
      final parts = v.trim().replaceAll('v', '').split('.');
      if (parts.length >= 2) {
        final maj = int.tryParse(parts[0]) ?? 1;
        final min = int.tryParse(parts[1]) ?? 0;
        parsedVersions.add((major: maj, minor: min));
      }
    }

    if (parsedVersions.isEmpty) return '1.0';

    parsedVersions.sort((a, b) {
      if (a.major != b.major) return b.major.compareTo(a.major);
      return b.minor.compareTo(a.minor);
    });

    final latest = parsedVersions.first;
    return '${latest.major}.${latest.minor + 1}';
  }
}
