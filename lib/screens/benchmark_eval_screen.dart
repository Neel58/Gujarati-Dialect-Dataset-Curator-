import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gsip_models.dart';
import '../services/evaluation_engine.dart';
import 'missions_screen.dart';

final modelEvaluationsProvider = FutureProvider<List<ModelEvaluation>>((ref) async {
  final repo = ref.watch(gsipRepositoryProvider);
  return repo.fetchModelEvaluations();
});

class BenchmarkEvalScreen extends ConsumerStatefulWidget {
  const BenchmarkEvalScreen({super.key});

  @override
  ConsumerState<BenchmarkEvalScreen> createState() => _BenchmarkEvalScreenState();
}

class _BenchmarkEvalScreenState extends ConsumerState<BenchmarkEvalScreen> {
  BenchmarkEvaluationSummary? _latestEvaluation;
  String? _evaluatedModelName;

  static const List<BenchmarkEvaluationInput> fallbackBenchmarkSuite = [
    BenchmarkEvaluationInput(
      id: '00000000-0000-0000-0000-000000000101',
      reference: 'નમસ્તે ગુજરાત કેમ છો બધા',
      hypothesis: '',
      category: 'standard',
    ),
    BenchmarkEvaluationInput(
      id: '00000000-0000-0000-0000-000000000102',
      reference: 'આજે હવામાન ખૂબ સુંદર છે',
      hypothesis: '',
      category: 'standard',
    ),
    BenchmarkEvaluationInput(
      id: '00000000-0000-0000-0000-000000000103',
      reference: 'હું કાલે સવારે સુરત જવાનો છું',
      hypothesis: '',
      category: 'surti',
      dialectId: 3,
    ),
    BenchmarkEvaluationInput(
      id: '00000000-0000-0000-0000-000000000104',
      reference: 'તમે ક્યાં ગામના રહેવાસી છો ભાઈ',
      hypothesis: '',
      category: 'kathiyawadi',
      dialectId: 2,
    ),
    BenchmarkEvaluationInput(
      id: '00000000-0000-0000-0000-000000000105',
      reference: 'આ દવા દિવસમાં બે વાર લેવાની છે',
      hypothesis: '',
      category: 'healthcare',
      domainId: 'healthcare',
    ),
    BenchmarkEvaluationInput(
      id: '00000000-0000-0000-0000-000000000106',
      reference: 'હાલો આપડે ખેતરે જાઈએ',
      hypothesis: '',
      category: 'kathiyawadi',
      dialectId: 2,
    ),
    BenchmarkEvaluationInput(
      id: '00000000-0000-0000-0000-000000000107',
      reference: 'હેલો અવાજ સંભળાય છે બરોબર',
      hypothesis: '',
      category: 'telephone',
      environmentId: 'telephone',
    ),
  ];

  void _openRunEvaluationDialog() async {
    final repo = ref.read(gsipRepositoryProvider);

    // Load benchmark and items dynamically from database
    List<BenchmarkEvaluationInput> benchmarkSuite = fallbackBenchmarkSuite;
    String activeBenchmarkVersionId = '00000000-0000-0000-0000-000000000010';
    try {
      final benchmarks = await repo.fetchBenchmarks();
      if (benchmarks.isNotEmpty) {
        final bId = benchmarks.first['id'] as String;
        final versions = await repo.fetchBenchmarkVersions(bId);
        if (versions.isNotEmpty) {
          activeBenchmarkVersionId = versions.first['id'] as String;
        }
      }
      final dbItems = await repo.fetchBenchmarkItems(activeBenchmarkVersionId);
      if (dbItems.isNotEmpty) {
        benchmarkSuite = dbItems.map((m) => BenchmarkEvaluationInput(
          id: m['id'] as String,
          reference: m['reference_transcript'] as String,
          hypothesis: '',
          category: m['category'] as String,
          dialectId: m['dialect_id'] as int?,
          domainId: m['domain_id'] as String?,
          environmentId: m['environment_id'] as String?,
        )).toList();
      }
    } catch (e) {
      debugPrint('Notice: Using baseline benchmark suite ($e)');
    }

    if (!mounted) return;

    final modelNameCtrl = TextEditingController(text: 'Gujarati-ASR-Wav2Vec2');
    final versionCtrl = TextEditingController(text: 'v1.0-checkpoint');

    final predictionControllers = benchmarkSuite.map((item) {
      String defaultHyp = item.reference;
      if (item.category == 'kathiyawadi') {
        defaultHyp = item.reference.replaceAll('જાઈએ', 'જાવ');
      } else if (item.category == 'telephone') {
        defaultHyp = item.reference.replaceAll('બરોબર', '');
      }
      return TextEditingController(text: defaultHyp);
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Evaluate Speech Model Predictions'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Benchmark: Gujarati ASR Robustness Benchmark (v1.0)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: modelNameCtrl,
                          decoration: const InputDecoration(labelText: 'Model Name'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: versionCtrl,
                          decoration: const InputDecoration(labelText: 'Model Version / Checkpoint'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Benchmark Items & Model Predictions:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(benchmarkSuite.length, (idx) {
                    final item = benchmarkSuite[idx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Chip(
                                  label: Text(item.category.toUpperCase(), style: const TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('Ref: "${item.reference}"', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: predictionControllers[idx],
                              decoration: const InputDecoration(
                                labelText: 'Model Prediction (Hypothesis)',
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton.icon(
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Compute WER / CER'),
              onPressed: () async {
                final evalItems = List.generate(benchmarkSuite.length, (idx) {
                  final base = benchmarkSuite[idx];
                  return BenchmarkEvaluationInput(
                    id: base.id,
                    reference: base.reference,
                    hypothesis: predictionControllers[idx].text.trim(),
                    category: base.category,
                    dialectId: base.dialectId,
                    domainId: base.domainId,
                    environmentId: base.environmentId,
                  );
                });

                final summary = EvaluationEngine.evaluateBatch(evalItems);

                // Persist evaluation and results to Supabase (Feature 9)
                try {
                  await repo.recordModelEvaluation(
                    benchmarkVersionId: activeBenchmarkVersionId,
                    modelName: modelNameCtrl.text.trim(),
                    modelVersion: versionCtrl.text.trim(),
                    overallWer: summary.overallWer,
                    overallCer: summary.overallCer,
                    categoryMetrics: summary.categoryBreakdown.map((k, v) => MapEntry(k, v.toJson())),
                    failureSummary: {
                      'substitutions': summary.totalSubstitutions,
                      'deletions': summary.totalDeletions,
                      'insertions': summary.totalInsertions,
                      'worst_samples': summary.worstSamples.map((s) => s.toJson()).toList(),
                    },
                    results: evalItems.map((it) {
                      final align = EvaluationEngine.align(it.reference, it.hypothesis);
                      return EvaluationResult(
                        id: '',
                        evaluationId: '',
                        benchmarkItemId: it.id,
                        hypothesis: it.hypothesis,
                        reference: it.reference,
                        wer: align.wer,
                        cer: align.cer,
                        substitutions: align.substitutions,
                        deletions: align.deletions,
                        insertions: align.insertions,
                      );
                    }).toList(),
                  );
                  ref.invalidate(modelEvaluationsProvider);
                } catch (e) {
                  debugPrint('Notice: Local evaluation recorded (DB sync: $e)');
                }

                setState(() {
                  _latestEvaluation = summary;
                  _evaluatedModelName = '${modelNameCtrl.text.trim()} (${versionCtrl.text.trim()})';
                });

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Evaluation complete & saved: Overall WER ${(summary.overallWer * 100).toStringAsFixed(1)}%',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deployRecommendedMission(ModelFailureRecommendation rec) async {
    final repo = ref.read(gsipRepositoryProvider);

    final mission = Mission(
      id: '',
      title: 'Failure Resolution: ${rec.title}',
      description: rec.description,
      taskType: MissionTaskType.recording,
      status: MissionStatus.active,
      requiredDialectId: rec.dialectId != null ? int.tryParse(rec.dialectId!) : null,
      requiredDomainId: rec.domainId,
      requiredEnvironmentId: rec.environmentId,
      targetQuantity: rec.recommendedHours * 20,
      priority: rec.priority == 'high' ? 9 : 6,
      tags: ['model-failure-resolution', rec.targetCategory],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await repo.createMission(mission);
      ref.invalidate(missionsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created mission: "${mission.title}"'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MissionsScreen()),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to deploy mission: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(modelEvaluationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech AI Benchmark & Evaluation'),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Run Evaluation'),
            onPressed: _openRunEvaluationDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Benchmark Card
            Card(
              color: Colors.deepPurple.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified, color: Colors.deepPurple),
                        SizedBox(width: 8),
                        Text(
                          'Gujarati ASR Robustness Benchmark',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                        ),
                        Spacer(),
                        Chip(
                          label: Text('Version 1.0 (Immutable)'),
                          backgroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Evaluates ASR models across standard Gujarati, regional Kathiyawadi & Surti dialects, medical domain terminology, and telephone channel degradations.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_latestEvaluation != null) ...[
              // Results Header
              Text(
                'Evaluation Results: ${_evaluatedModelName ?? ""}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // KPI Row
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'Overall WER',
                      value: '${(_latestEvaluation!.overallWer * 100).toStringAsFixed(1)}%',
                      subtitle: 'Word Error Rate',
                      color: _latestEvaluation!.overallWer < 0.15 ? Colors.teal : Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      title: 'Overall CER',
                      value: '${(_latestEvaluation!.overallCer * 100).toStringAsFixed(1)}%',
                      subtitle: 'Character Error Rate',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      title: 'Alignment Errors',
                      value: '${_latestEvaluation!.totalSubstitutions + _latestEvaluation!.totalDeletions + _latestEvaluation!.totalInsertions}',
                      subtitle: 'Sub: ${_latestEvaluation!.totalSubstitutions}, Del: ${_latestEvaluation!.totalDeletions}, Ins: ${_latestEvaluation!.totalInsertions}',
                      color: Colors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recommendations Section (FEATURE 11)
              if (_latestEvaluation!.recommendations.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber),
                    const SizedBox(width: 8),
                    const Text(
                      'AI Data Recommendations from Model Failures',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'The platform detected high error patterns in specific slices. Deploy targeted collection missions directly to remediate these model weaknesses.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ..._latestEvaluation!.recommendations.map((rec) {
                  return Card(
                    color: Colors.amber.shade50,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.amber.shade400),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                rec.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const Spacer(),
                              Text(
                                'WER: ${(rec.observedWer * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(rec.description, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.add_task, size: 16),
                                label: const Text('Create Collection Mission'),
                                style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
                                onPressed: () => _deployRecommendedMission(rec),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],

              // Category Breakdown Table
              const Text(
                'Category Error Rate Breakdown',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _latestEvaluation!.categoryBreakdown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final catName = _latestEvaluation!.categoryBreakdown.keys.elementAt(idx);
                    final m = _latestEvaluation!.categoryBreakdown[catName]!;
                    final percentWer = (m.wer * 100).toStringAsFixed(1);
                    final percentCer = (m.cer * 100).toStringAsFixed(1);

                    return ListTile(
                      title: Text(catName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${m.sampleCount} samples • Subs: ${m.substitutions}, Dels: ${m.deletions}, Ins: ${m.insertions}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('WER: $percentWer%', style: TextStyle(fontWeight: FontWeight.bold, color: m.wer > 0.2 ? Colors.red : Colors.green)),
                          Text('CER: $percentCer%', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
            ],

            // Historical Evaluation Runs Section (Feature 9 persistence)
            Row(
              children: [
                const Icon(Icons.history, color: Colors.deepPurple),
                const SizedBox(width: 8),
                const Text(
                  'Historical Model Evaluations',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            historyAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error loading history: $e', style: const TextStyle(color: Colors.red)),
              data: (history) {
                if (history.isEmpty && _latestEvaluation == null) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Column(
                          children: [
                            const Text('No model evaluations recorded yet.'),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Run First Evaluation'),
                              onPressed: _openRunEvaluationDialog,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                if (history.isEmpty) {
                  return const Text('Evaluation saved to database.', style: TextStyle(color: Colors.grey));
                }

                return Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: history.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = history[i];
                      final werPercent = item.overallWer != null ? '${(item.overallWer! * 100).toStringAsFixed(1)}%' : 'N/A';
                      final cerPercent = item.overallCer != null ? '${(item.overallCer! * 100).toStringAsFixed(1)}%' : 'N/A';

                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.analytics_outlined)),
                        title: Text(item.modelName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Version: ${item.modelVersion ?? "latest"} • Status: ${item.status}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('WER: $werPercent', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                            Text('CER: $cerPercent', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
