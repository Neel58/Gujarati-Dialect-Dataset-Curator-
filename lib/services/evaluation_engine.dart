import 'dart:math';

/// Detailed result of evaluating a single reference/hypothesis pair.
class AlignmentResult {
  final String reference;
  final String hypothesis;
  final int referenceWordCount;
  final int hypothesisWordCount;
  final int substitutions;
  final int deletions;
  final int insertions;
  final int correctWords;
  final double wer;
  final int referenceCharCount;
  final int hypothesisCharCount;
  final int charSubstitutions;
  final int charDeletions;
  final int charInsertions;
  final double cer;

  const AlignmentResult({
    required this.reference,
    required this.hypothesis,
    required this.referenceWordCount,
    required this.hypothesisWordCount,
    required this.substitutions,
    required this.deletions,
    required this.insertions,
    required this.correctWords,
    required this.wer,
    required this.referenceCharCount,
    required this.hypothesisCharCount,
    required this.charSubstitutions,
    required this.charDeletions,
    required this.charInsertions,
    required this.cer,
  });

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'hypothesis': hypothesis,
        'substitutions': substitutions,
        'deletions': deletions,
        'insertions': insertions,
        'wer': wer,
        'cer': cer,
      };
}

/// Category evaluation summary metrics.
class CategoryMetrics {
  final String category;
  final int sampleCount;
  final int totalRefWords;
  final int totalErrors;
  final double wer;
  final double cer;
  final int substitutions;
  final int deletions;
  final int insertions;

  const CategoryMetrics({
    required this.category,
    required this.sampleCount,
    required this.totalRefWords,
    required this.totalErrors,
    required this.wer,
    required this.cer,
    required this.substitutions,
    required this.deletions,
    required this.insertions,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        'sample_count': sampleCount,
        'total_ref_words': totalRefWords,
        'wer': wer,
        'cer': cer,
        'substitutions': substitutions,
        'deletions': deletions,
        'insertions': insertions,
      };
}

/// An actionable recommendation derived from model failure patterns.
class ModelFailureRecommendation {
  final String title;
  final String description;
  final String priority; // 'high', 'medium', 'low'
  final String targetCategory;
  final String? dialectId;
  final String? domainId;
  final String? environmentId;
  final int recommendedHours;
  final double observedWer;

  const ModelFailureRecommendation({
    required this.title,
    required this.description,
    required this.priority,
    required this.targetCategory,
    this.dialectId,
    this.domainId,
    this.environmentId,
    required this.recommendedHours,
    required this.observedWer,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'priority': priority,
        'target_category': targetCategory,
        'dialect_id': dialectId,
        'domain_id': domainId,
        'environment_id': environmentId,
        'recommended_hours': recommendedHours,
        'observed_wer': observedWer,
      };
}

/// Complete benchmark evaluation outcome.
class BenchmarkEvaluationSummary {
  final double overallWer;
  final double overallCer;
  final int totalSamples;
  final int totalReferenceWords;
  final int totalSubstitutions;
  final int totalDeletions;
  final int totalInsertions;
  final Map<String, CategoryMetrics> categoryBreakdown;
  final List<AlignmentResult> worstSamples;
  final List<ModelFailureRecommendation> recommendations;

  const BenchmarkEvaluationSummary({
    required this.overallWer,
    required this.overallCer,
    required this.totalSamples,
    required this.totalReferenceWords,
    required this.totalSubstitutions,
    required this.totalDeletions,
    required this.totalInsertions,
    required this.categoryBreakdown,
    required this.worstSamples,
    required this.recommendations,
  });

  Map<String, dynamic> toJson() => {
        'overall_wer': overallWer,
        'overall_cer': overallCer,
        'total_samples': totalSamples,
        'total_substitutions': totalSubstitutions,
        'total_deletions': totalDeletions,
        'total_insertions': totalInsertions,
        'category_metrics': categoryBreakdown
            .map((k, v) => MapEntry(k, v.toJson())),
        'worst_samples': worstSamples.map((s) => s.toJson()).toList(),
        'recommendations':
            recommendations.map((r) => r.toJson()).toList(),
      };
}

/// Benchmark item input for evaluation.
class BenchmarkEvaluationInput {
  final String id;
  final String reference;
  final String hypothesis;
  final String category;
  final int? dialectId;
  final String? domainId;
  final String? environmentId;

  const BenchmarkEvaluationInput({
    required this.id,
    required this.reference,
    required this.hypothesis,
    required this.category,
    this.dialectId,
    this.domainId,
    this.environmentId,
  });
}

/// EvaluationEngine computes Word Error Rate (WER) and Character Error Rate (CER)
/// using exact Levenshtein dynamic programming alignment.
///
/// It does NOT fake metrics and provides mathematical explanations and alignments.
class EvaluationEngine {
  /// Normalize text: trims extra whitespace, converts multiple spaces to single space.
  static String normalize(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Tokenize into words by whitespace.
  static List<String> tokenizeWords(String text) {
    final norm = normalize(text);
    if (norm.isEmpty) return [];
    return norm.split(' ');
  }

  /// Tokenize into grapheme characters (ignoring spaces for CER).
  static List<String> tokenizeChars(String text) {
    final norm = normalize(text);
    return norm.replaceAll(RegExp(r'\s+'), '').split('');
  }

  /// Compute exact Levenshtein distance matrix and backtrack to count
  /// substitutions, deletions, and insertions.
  static ({
    int distance,
    int substitutions,
    int deletions,
    int insertions,
    int correct,
  }) computeAlignment(List<String> ref, List<String> hyp) {
    final n = ref.length;
    final m = hyp.length;

    if (n == 0) {
      return (
        distance: m,
        substitutions: 0,
        deletions: 0,
        insertions: m,
        correct: 0,
      );
    }
    if (m == 0) {
      return (
        distance: n,
        substitutions: 0,
        deletions: n,
        insertions: 0,
        correct: 0,
      );
    }

    // DP table: d[i][j]
    final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

    for (int i = 0; i <= n; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= m; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        final cost = (ref[i - 1] == hyp[j - 1]) ? 0 : 1;
        d[i][j] = min(
          d[i - 1][j] + 1, // deletion from ref
          min(
            d[i][j - 1] + 1, // insertion into hyp
            d[i - 1][j - 1] + cost, // match or substitution
          ),
        );
      }
    }

    // Backtrack to find exact counts
    int i = n;
    int j = m;
    int sub = 0;
    int del = 0;
    int ins = 0;
    int correct = 0;

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0) {
        final cost = (ref[i - 1] == hyp[j - 1]) ? 0 : 1;
        if (d[i][j] == d[i - 1][j - 1] + cost) {
          if (cost == 1) {
            sub++;
          } else {
            correct++;
          }
          i--;
          j--;
          continue;
        }
      }
      if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
        del++;
        i--;
        continue;
      }
      if (j > 0 && d[i][j] == d[i][j - 1] + 1) {
        ins++;
        j--;
        continue;
      }
      // Fallback
      if (i > 0) {
        del++;
        i--;
      } else if (j > 0) {
        ins++;
        j--;
      }
    }

    return (
      distance: d[n][m],
      substitutions: sub,
      deletions: del,
      insertions: ins,
      correct: correct,
    );
  }

  /// Align a single reference and hypothesis, returning full metrics.
  static AlignmentResult align(String reference, String hypothesis) {
    final refWords = tokenizeWords(reference);
    final hypWords = tokenizeWords(hypothesis);
    final wordAlign = computeAlignment(refWords, hypWords);

    final double wer;
    if (refWords.isEmpty) {
      wer = hypWords.isEmpty ? 0.0 : 1.0;
    } else {
      wer = (wordAlign.substitutions + wordAlign.deletions + wordAlign.insertions) /
          refWords.length;
    }

    final refChars = tokenizeChars(reference);
    final hypChars = tokenizeChars(hypothesis);
    final charAlign = computeAlignment(refChars, hypChars);

    final double cer;
    if (refChars.isEmpty) {
      cer = hypChars.isEmpty ? 0.0 : 1.0;
    } else {
      cer = (charAlign.substitutions + charAlign.deletions + charAlign.insertions) /
          refChars.length;
    }

    return AlignmentResult(
      reference: reference,
      hypothesis: hypothesis,
      referenceWordCount: refWords.length,
      hypothesisWordCount: hypWords.length,
      substitutions: wordAlign.substitutions,
      deletions: wordAlign.deletions,
      insertions: wordAlign.insertions,
      correctWords: wordAlign.correct,
      wer: wer,
      referenceCharCount: refChars.length,
      hypothesisCharCount: hypChars.length,
      charSubstitutions: charAlign.substitutions,
      charDeletions: charAlign.deletions,
      charInsertions: charAlign.insertions,
      cer: cer,
    );
  }

  /// Evaluate an entire batch of benchmark items with predictions.
  static BenchmarkEvaluationSummary evaluateBatch(
      List<BenchmarkEvaluationInput> items) {
    if (items.isEmpty) {
      return const BenchmarkEvaluationSummary(
        overallWer: 0.0,
        overallCer: 0.0,
        totalSamples: 0,
        totalReferenceWords: 0,
        totalSubstitutions: 0,
        totalDeletions: 0,
        totalInsertions: 0,
        categoryBreakdown: {},
        worstSamples: [],
        recommendations: [],
      );
    }

    int totalRefWords = 0;
    int totalSubs = 0;
    int totalDels = 0;
    int totalIns = 0;

    int totalRefChars = 0;
    int totalCharSubs = 0;
    int totalCharDels = 0;
    int totalCharIns = 0;

    final alignments = <AlignmentResult>[];
    final categoryMap = <String, List<({BenchmarkEvaluationInput item, AlignmentResult align})>>{};

    for (final it in items) {
      final res = align(it.reference, it.hypothesis);
      alignments.add(res);

      totalRefWords += res.referenceWordCount;
      totalSubs += res.substitutions;
      totalDels += res.deletions;
      totalIns += res.insertions;

      totalRefChars += res.referenceCharCount;
      totalCharSubs += res.charSubstitutions;
      totalCharDels += res.charDeletions;
      totalCharIns += res.charInsertions;

      final catKey = it.category.trim().toLowerCase();
      categoryMap.putIfAbsent(catKey, () => []).add((item: it, align: res));
    }

    final double overallWer = totalRefWords > 0
        ? (totalSubs + totalDels + totalIns) / totalRefWords
        : 0.0;

    final double overallCer = totalRefChars > 0
        ? (totalCharSubs + totalCharDels + totalCharIns) / totalRefChars
        : 0.0;

    // Category breakdown
    final categoryBreakdown = <String, CategoryMetrics>{};
    for (final entry in categoryMap.entries) {
      final cat = entry.key;
      final pairs = entry.value;

      int catRefWords = 0;
      int catSubs = 0;
      int catDels = 0;
      int catIns = 0;

      int catRefChars = 0;
      int catCharSubs = 0;
      int catCharDels = 0;
      int catCharIns = 0;

      for (final p in pairs) {
        catRefWords += p.align.referenceWordCount;
        catSubs += p.align.substitutions;
        catDels += p.align.deletions;
        catIns += p.align.insertions;

        catRefChars += p.align.referenceCharCount;
        catCharSubs += p.align.charSubstitutions;
        catCharDels += p.align.charDeletions;
        catCharIns += p.align.charInsertions;
      }

      final catWer = catRefWords > 0
          ? (catSubs + catDels + catIns) / catRefWords
          : 0.0;
      final catCer = catRefChars > 0
          ? (catCharSubs + catCharDels + catCharIns) / catRefChars
          : 0.0;

      categoryBreakdown[cat] = CategoryMetrics(
        category: cat,
        sampleCount: pairs.length,
        totalRefWords: catRefWords,
        totalErrors: catSubs + catDels + catIns,
        wer: catWer,
        cer: catCer,
        substitutions: catSubs,
        deletions: catDels,
        insertions: catIns,
      );
    }

    // Sort worst samples by WER descending
    final worstSorted = List<AlignmentResult>.from(alignments)
      ..sort((a, b) => b.wer.compareTo(a.wer));
    final worstSamples = worstSorted.take(5).toList();

    // Generate actionable data recommendations from failure analysis
    final recommendations = _generateRecommendations(
      overallWer: overallWer,
      categories: categoryBreakdown,
      items: items,
    );

    return BenchmarkEvaluationSummary(
      overallWer: overallWer,
      overallCer: overallCer,
      totalSamples: items.length,
      totalReferenceWords: totalRefWords,
      totalSubstitutions: totalSubs,
      totalDeletions: totalDels,
      totalInsertions: totalIns,
      categoryBreakdown: categoryBreakdown,
      worstSamples: worstSamples,
      recommendations: recommendations,
    );
  }

  /// Generate concrete data collection recommendations from failure patterns.
  static List<ModelFailureRecommendation> _generateRecommendations({
    required double overallWer,
    required Map<String, CategoryMetrics> categories,
    required List<BenchmarkEvaluationInput> items,
  }) {
    final recs = <ModelFailureRecommendation>[];

    // Find categories where WER significantly exceeds overall WER (or is > 20%)
    for (final entry in categories.entries) {
      final cat = entry.key;
      final metric = entry.value;

      final isHighError = metric.wer > 0.20 ||
          (overallWer > 0 && metric.wer >= (overallWer * 1.25));

      if (isHighError) {
        final percentWer = (metric.wer * 100).toStringAsFixed(1);
        final percentOverall = (overallWer * 100).toStringAsFixed(1);

        // Find associated dialect, domain, environment if any from items
        final matchingItem = items.firstWhere(
          (it) => it.category.trim().toLowerCase() == cat,
          orElse: () => items.first,
        );

        final priority = metric.wer >= 0.30 ? 'high' : 'medium';
        final recommendedHours = metric.wer >= 0.30 ? 25 : 10;

        recs.add(ModelFailureRecommendation(
          title: 'High Error Rate in "$cat" Category',
          description:
              'Observed WER is $percentWer% (vs overall $percentOverall%). '
              'Prioritize targeted collection of $cat speech with natural acoustic variations.',
          priority: priority,
          targetCategory: cat,
          dialectId: matchingItem.dialectId?.toString(),
          domainId: matchingItem.domainId,
          environmentId: matchingItem.environmentId,
          recommendedHours: recommendedHours,
          observedWer: metric.wer,
        ));
      }
    }

    return recs;
  }
}
