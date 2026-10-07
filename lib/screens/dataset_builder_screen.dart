import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gsip_models.dart';
import '../services/dataset_builder_service.dart';
import 'missions_screen.dart';

final datasetsProvider = FutureProvider<List<Dataset>>((ref) async {
  final repo = ref.watch(gsipRepositoryProvider);
  return repo.fetchDatasets();
});

class DatasetBuilderScreen extends ConsumerStatefulWidget {
  const DatasetBuilderScreen({super.key});

  @override
  ConsumerState<DatasetBuilderScreen> createState() => _DatasetBuilderScreenState();
}

class _DatasetBuilderScreenState extends ConsumerState<DatasetBuilderScreen> {
  void _openBuildDialog(Dataset? existingDataset) async {
    final repo = ref.read(gsipRepositoryProvider);
    final allAssets = await repo.fetchDataAssets(limit: 500);

    if (!mounted) return;

    final nameCtrl = TextEditingController(text: existingDataset?.name ?? '');
    final descCtrl = TextEditingController(text: existingDataset?.description ?? '');
    String versionStr = '1.0';

    if (existingDataset != null) {
      final versions = await repo.fetchDatasetVersions(existingDataset.id);
      versionStr = DatasetBuilderService.suggestNextVersion(versions.map((v) => v.version).toList());
    }

    int? selectedDialectId;
    String? selectedDomain;
    int minQuality = 80;
    String consentType = 'commercial_ai';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final criteria = DatasetFilterCriteria(
            dialectIds: selectedDialectId != null ? [selectedDialectId!] : null,
            domainIds: selectedDomain != null ? [selectedDomain!] : null,
            minQualityScore: minQuality,
            requiredConsentType: consentType,
          );

          final evaluation = DatasetBuilderService.evaluateAssets(
            allAssets: allAssets,
            criteria: criteria,
          );

          final eligibleHours = evaluation.totalDurationMs / (1000.0 * 3600.0);

          return AlertDialog(
            title: Text(existingDataset == null ? 'Build New Dataset' : 'Create Version $versionStr'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (existingDataset == null) ...[
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Dataset Name', hintText: 'e.g. Kathiyawadi Healthcare ASR'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Version Notes / Description'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Filter Criteria & Governance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedDialectId,
                      decoration: const InputDecoration(labelText: 'Dialect Filter'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All Dialects')),
                        DropdownMenuItem(value: 1, child: Text('Standard Gujarati')),
                        DropdownMenuItem(value: 2, child: Text('Kathiyawadi')),
                        DropdownMenuItem(value: 3, child: Text('Surti')),
                        DropdownMenuItem(value: 4, child: Text('Charotari')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedDialectId = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedDomain,
                      decoration: const InputDecoration(labelText: 'Domain Filter'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All Domains')),
                        DropdownMenuItem(value: 'healthcare', child: Text('Healthcare')),
                        DropdownMenuItem(value: 'agriculture', child: Text('Agriculture')),
                        DropdownMenuItem(value: 'education', child: Text('Education')),
                        DropdownMenuItem(value: 'general', child: Text('General')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedDomain = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: consentType,
                      decoration: const InputDecoration(labelText: 'Target Consent Scope'),
                      items: const [
                        DropdownMenuItem(value: 'commercial_ai', child: Text('Commercial AI (Excludes Research-Only)')),
                        DropdownMenuItem(value: 'research_only', child: Text('Research Only (All Consented)')),
                        DropdownMenuItem(value: 'open', child: Text('Open Distribution Only')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => consentType = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Minimum Quality Threshold: $minQuality / 100'),
                    Slider(
                      value: minQuality.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$minQuality',
                      onChanged: (v) => setDialogState(() => minQuality = v.toInt()),
                    ),
                    const Divider(),
                    // Real-time Candidate Statistics
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Live Criteria Evaluation', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                          const SizedBox(height: 6),
                          Text('✓ Eligible Assets: ${evaluation.eligibleAssets.length} (${eligibleHours.toStringAsFixed(2)} hrs)'),
                          Text('✓ Unique Speakers: ${evaluation.uniqueSpeakers}'),
                          Text('✓ Avg Quality: ${evaluation.averageQualityScore.toStringAsFixed(1)} / 100'),
                          if (evaluation.excludedAssets.isNotEmpty)
                            Text('✗ Excluded: ${evaluation.excludedAssets.length} items (insufficient consent / review)', style: const TextStyle(fontSize: 12, color: Colors.brown)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (existingDataset == null && nameCtrl.text.trim().isEmpty) return;

                  try {
                    Dataset targetDataset = existingDataset ??
                        await repo.createDataset(
                          name: nameCtrl.text.trim(),
                          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                        );

                    await repo.createDatasetVersion(
                      datasetId: targetDataset.id,
                      version: versionStr,
                      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                      filterCriteria: criteria.toJson(),
                      assetIds: evaluation.eligibleAssets.map((a) => a.id).toList(),
                      assetCount: evaluation.eligibleAssets.length,
                      totalDurationMs: evaluation.totalDurationMs,
                      speakerCount: evaluation.uniqueSpeakers,
                      dialectDistribution: evaluation.dialectDistribution,
                      domainDistribution: evaluation.domainDistribution,
                      averageQualityScore: evaluation.averageQualityScore,
                      consentSummary: evaluation.consentDistribution,
                    );

                    if (ctx.mounted) Navigator.pop(ctx);
                    ref.invalidate(datasetsProvider);

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Dataset version $versionStr created successfully!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  }
                },
                child: const Text('Create Version'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _viewDatasetVersions(Dataset dataset) async {
    final repo = ref.read(gsipRepositoryProvider);
    final versions = await repo.fetchDatasetVersions(dataset.id);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${dataset.name} — Versions',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Version'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openBuildDialog(dataset);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              Expanded(
                child: versions.isEmpty
                    ? const Center(child: Text('No versions created yet.'))
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: versions.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, i) {
                          final v = versions[i];
                          return ListTile(
                            title: Row(
                              children: [
                                Text('Version ${v.version}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                if (v.isPublished)
                                  const Chip(
                                    label: Text('PUBLISHED & IMMUTABLE', style: TextStyle(fontSize: 9, color: Colors.white)),
                                    backgroundColor: Colors.teal,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('${v.assetCount} assets • ${v.totalHours.toStringAsFixed(2)} hours • ${v.speakerCount} speakers'),
                                if (v.averageQualityScore != null)
                                  Text('Avg Quality: ${v.averageQualityScore!.toStringAsFixed(1)} / 100'),
                              ],
                            ),
                            trailing: !v.isPublished
                                ? OutlinedButton(
                                    child: const Text('Publish'),
                                    onPressed: () async {
                                      await repo.publishDatasetVersion(v.id);
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) _viewDatasetVersions(dataset);
                                    },
                                  )
                                : const Icon(Icons.lock, color: Colors.teal, size: 20),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final datasetsAsync = ref.watch(datasetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Datasets & Versioning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Build New Dataset',
            onPressed: () => _openBuildDialog(null),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(datasetsProvider),
          ),
        ],
      ),
      body: datasetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $err'),
              ElevatedButton(
                onPressed: () => ref.invalidate(datasetsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (datasets) {
          if (datasets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text('No datasets configured yet.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Construct reusable, versioned datasets from approved Gujarati speech assets with strict consent boundaries.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Build First Dataset'),
                      onPressed: () => _openBuildDialog(null),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: datasets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final d = datasets[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
                  title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(d.description ?? 'Curated speech dataset'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _viewDatasetVersions(d),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
