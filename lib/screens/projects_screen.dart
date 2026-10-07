import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gsip_models.dart';
import '../services/dataset_builder_service.dart';
import 'missions_screen.dart';

final dataProjectsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(gsipRepositoryProvider);
  return repo.fetchDataProjects();
});

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  void _openCreateProjectDialog() async {
    final repo = ref.read(gsipRepositoryProvider);
    final allAssets = await repo.fetchDataAssets(
      reviewStatus: ReviewStatus.approved,
      limit: 500,
    );

    if (!mounted) return;

    final nameCtrl = TextEditingController(text: 'Gujarati Healthcare ASR');
    final descCtrl = TextEditingController(
      text: 'Targeted speech collection for medical terms and symptom inquiries',
    );
    double targetHours = 20.0;
    String selectedDomain = 'healthcare';
    int minQuality = 80;
    String consentType = 'commercial_ai';
    int? selectedDialectId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Calculate existing usable hours matching project criteria
          final eval = DatasetBuilderService.evaluateAssets(
            allAssets: allAssets,
            criteria: DatasetFilterCriteria(
              domainIds: [selectedDomain],
              dialectIds: selectedDialectId != null ? [selectedDialectId!] : null,
              minQualityScore: minQuality,
              requiredConsentType: consentType,
            ),
          );

          final existingHours = eval.totalDurationMs / (1000.0 * 3600.0);
          final missingHours = (targetHours - existingHours).clamp(0.0, targetHours);
          final progressFraction = targetHours > 0 ? (existingHours / targetHours).clamp(0.0, 1.0) : 0.0;

          return AlertDialog(
            title: const Text('New Data Requirement Project'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Project Name',
                        hintText: 'e.g. Gujarati Healthcare ASR',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Description / Purpose'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: targetHours.toStringAsFixed(0),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Target Hours'),
                            onChanged: (v) => targetHours = double.tryParse(v) ?? 20.0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedDomain,
                            decoration: const InputDecoration(labelText: 'Domain'),
                            items: const [
                              DropdownMenuItem(value: 'healthcare', child: Text('Healthcare')),
                              DropdownMenuItem(value: 'agriculture', child: Text('Agriculture')),
                              DropdownMenuItem(value: 'education', child: Text('Education')),
                              DropdownMenuItem(value: 'general', child: Text('General')),
                            ],
                            onChanged: (v) {
                              if (v != null) setDialogState(() => selectedDomain = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedDialectId,
                      decoration: const InputDecoration(labelText: 'Target Dialect'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Multiple / Any Dialects')),
                        DropdownMenuItem(value: 1, child: Text('Standard Gujarati')),
                        DropdownMenuItem(value: 2, child: Text('Kathiyawadi')),
                        DropdownMenuItem(value: 3, child: Text('Surti')),
                        DropdownMenuItem(value: 4, child: Text('Charotari')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedDialectId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: consentType,
                      decoration: const InputDecoration(labelText: 'Consent Scope'),
                      items: const [
                        DropdownMenuItem(value: 'commercial_ai', child: Text('Commercial AI')),
                        DropdownMenuItem(value: 'research_only', child: Text('Research Only')),
                        DropdownMenuItem(value: 'open', child: Text('Open Distribution')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => consentType = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    // Live Deficit Calculation
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Data Deficit Analysis',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          const SizedBox(height: 6),
                          Text('• Target Volume: ${targetHours.toStringAsFixed(1)} hours'),
                          Text('• Existing Usable Data: ${existingHours.toStringAsFixed(2)} hours (${eval.eligibleAssets.length} approved clips)'),
                          Text(
                            '• Missing Data Deficit: ${missingHours.toStringAsFixed(2)} hours',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: progressFraction,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                          ),
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
                  if (nameCtrl.text.trim().isEmpty) return;

                  try {
                    await repo.createDataProject(
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      requirements: {
                        'target_hours': targetHours,
                        'domain': selectedDomain,
                        'dialect_id': selectedDialectId,
                        'consent_scope': consentType,
                        'min_quality': minQuality,
                        'existing_hours': existingHours,
                        'missing_hours': missingHours,
                      },
                    );

                    // If there is missing data, deploy a collection mission directly
                    if (missingHours > 0) {
                      final neededClips = (missingHours * 240).round().clamp(10, 500);
                      await repo.createMission(
                        Mission(
                          id: '',
                          title: 'Project Collection: ${nameCtrl.text.trim()}',
                          description:
                              'Targeted collection for ${nameCtrl.text.trim()}: missing ${missingHours.toStringAsFixed(1)}h of data.',
                          taskType: MissionTaskType.recording,
                          status: MissionStatus.active,
                          requiredDialectId: selectedDialectId,
                          requiredDomainId: selectedDomain,
                          targetQuantity: neededClips,
                          priority: 9,
                          tags: ['project-requirement', selectedDomain],
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        ),
                      );
                      ref.invalidate(missionsProvider);
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    ref.invalidate(dataProjectsProvider);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Project requirement created and mission deployed!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  }
                },
                child: const Text('Create Project & Missions'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(dataProjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Requirements & Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Requirement',
            onPressed: _openCreateProjectDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(dataProjectsProvider),
          ),
        ],
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $err'),
              ElevatedButton(
                onPressed: () => ref.invalidate(dataProjectsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (projects) {
          if (projects.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'No organizational data projects yet.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Define research or AI speech targets (e.g. 50 hours Healthcare ASR). The platform will automatically calculate data gaps and generate required collection missions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Create Data Requirement'),
                      onPressed: _openCreateProjectDialog,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final p = projects[index];
              final req = (p['requirements'] as Map<String, dynamic>?) ?? {};
              final targetH = (req['target_hours'] as num?)?.toDouble() ?? 0.0;
              final existH = (req['existing_hours'] as num?)?.toDouble() ?? 0.0;
              final missH = (req['missing_hours'] as num?)?.toDouble() ?? targetH;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            p['name'] as String? ?? 'Untitled Project',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text((p['status'] as String? ?? 'active').toUpperCase(), style: const TextStyle(fontSize: 10)),
                            backgroundColor: Colors.teal.shade50,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      if (p['description'] != null) ...[
                        const SizedBox(height: 4),
                        Text(p['description'] as String, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Target: ${targetH.toStringAsFixed(0)}h', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Available: ${existH.toStringAsFixed(1)}h', style: const TextStyle(color: Colors.teal)),
                          Text('Deficit: ${missH.toStringAsFixed(1)}h', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: targetH > 0 ? (existH / targetH).clamp(0.0, 1.0) : 0.0,
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
