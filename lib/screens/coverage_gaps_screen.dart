import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gsip_models.dart';
import '../services/coverage_gap_engine.dart';
import 'missions_screen.dart';

final coverageReportProvider = FutureProvider<CorpusCoverageReport>((ref) async {
  final repo = ref.watch(gsipRepositoryProvider);
  final assets = await repo.fetchDataAssets(
    reviewStatus: ReviewStatus.approved,
    limit: 500,
  );
  return CoverageGapEngine.analyze(assets);
});

class CoverageGapsScreen extends ConsumerWidget {
  const CoverageGapsScreen({super.key});

  Future<void> _createMissionFromGap(
    BuildContext context,
    WidgetRef ref,
    CoverageGap gap,
  ) async {
    final proposal = gap.toMissionProposal();
    final repo = ref.read(gsipRepositoryProvider);

    final mission = Mission(
      id: '',
      title: proposal.title,
      description: proposal.description,
      taskType: proposal.taskType,
      status: MissionStatus.active,
      requiredDialectId: proposal.requiredDialectId,
      requiredDomainId: proposal.requiredDomainId,
      requiredEnvironmentId: proposal.requiredEnvironmentId,
      requiredAgeBand: proposal.requiredAgeBand,
      targetQuantity: proposal.targetQuantity,
      qualityThreshold: proposal.qualityThreshold,
      priority: proposal.priority,
      tags: proposal.tags,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await repo.createMission(mission);
      ref.invalidate(missionsProvider);
      ref.invalidate(coverageReportProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created mission: "${proposal.title}"'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MissionsScreen()),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create mission: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(coverageReportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Corpus Intelligence & Gaps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(coverageReportProvider),
          ),
        ],
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Error loading coverage data: $err', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(coverageReportProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (report) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(coverageReportProvider);
              await ref.read(coverageReportProvider.future);
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Cards
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          title: 'Approved Data',
                          value: '${report.totalHours.toStringAsFixed(1)} hrs',
                          subtitle: '${report.totalAssets} recordings',
                          icon: Icons.graphic_eq,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _KpiCard(
                          title: 'Contributors',
                          value: '${report.totalUniqueContributors}',
                          subtitle: 'Unique speakers',
                          icon: Icons.people_outline,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _KpiCard(
                          title: 'Avg Quality',
                          value: '${report.overallAverageQuality.toStringAsFixed(0)} / 100',
                          subtitle: 'Deterministic score',
                          icon: Icons.verified_outlined,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Actionable Gaps Section
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      const Text(
                        'Actionable Data Gaps',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Chip(
                        label: Text('${report.detectedGaps.length} Gaps Detected'),
                        backgroundColor: Colors.deepOrange.shade50,
                        labelStyle: const TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Identified under-represented dialect, domain, and demographic combinations. Click [Create Mission] to deploy a collection task.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  if (report.detectedGaps.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No critical coverage gaps detected! Target thresholds satisfied.'),
                      ),
                    )
                  else
                    ...report.detectedGaps.map((gap) {
                      final isHigh = gap.priority == 'high';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isHigh ? Colors.deepOrange.shade300 : Colors.grey.shade300,
                            width: isHigh ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isHigh ? Colors.deepOrange : Colors.amber.shade700,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isHigh ? 'HIGH PRIORITY GAP' : 'MEDIUM GAP',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    gap.dimension.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${gap.currentHours.toStringAsFixed(1)}h / ${gap.targetHours.toStringAsFixed(0)}h target',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                gap.title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                gap.description,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: gap.coverageRatio.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isHigh ? Colors.deepOrange : Colors.amber.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FilledButton.icon(
                                    icon: const Icon(Icons.add_task, size: 16),
                                    label: const Text('Create Mission'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isHigh ? Colors.deepOrange : Colors.deepPurple,
                                    ),
                                    onPressed: () => _createMissionFromGap(context, ref, gap),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  // Dialect Coverage Breakdown
                  const Text(
                    'Dialect Coverage Distribution',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...report.dialectCoverage.values.map((slice) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(slice.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                '${slice.totalHours.toStringAsFixed(1)}h (${slice.assetCount} clips, ${slice.uniqueSpeakers} speakers)',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: (slice.totalHours / 10.0).clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade200,
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 24),
                  // Domain Coverage Breakdown
                  const Text(
                    'Domain Slices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...report.domainCoverage.values.map((slice) {
                    if (slice.assetCount == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(slice.label),
                          Text('${slice.totalHours.toStringAsFixed(1)}h (${slice.assetCount} clips)'),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
