import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/gsip_repository.dart';
import '../models/gsip_models.dart';
import '../models/models.dart' as legacy;
import 'record_screen.dart';

final gsipRepositoryProvider = Provider<GsipRepository>((ref) => GsipRepository());

final missionsProvider = FutureProvider<List<Mission>>((ref) async {
  final repo = ref.watch(gsipRepositoryProvider);
  return repo.fetchMissions();
});

class MissionsScreen extends ConsumerStatefulWidget {
  final legacy.Profile? profile;
  const MissionsScreen({super.key, this.profile});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  MissionTaskType? _selectedTypeFilter;

  void _openCreateMissionDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int targetQty = 20;
    int priority = 8;
    MissionTaskType taskType = MissionTaskType.recording;
    int? selectedDialectId;
    String selectedDomain = 'general';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Collection Mission'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mission Title',
                    hintText: 'e.g. Kathiyawadi Healthcare Speech',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Objective & Instructions',
                    hintText: 'Explain target speech and requirements',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MissionTaskType>(
                  initialValue: taskType,
                  decoration: const InputDecoration(labelText: 'Task Type'),
                  items: MissionTaskType.values.map((t) {
                    final label = switch (t) {
                      MissionTaskType.recording => '🎙 Audio Recording',
                      MissionTaskType.transcriptionReview => '📝 Transcription Review',
                      MissionTaskType.metadataValidation => '🔍 Metadata Validation',
                      MissionTaskType.dialectValidation => '🗣 Dialect Validation',
                    };
                    return DropdownMenuItem(value: t, child: Text(label));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => taskType = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: selectedDialectId,
                  decoration: const InputDecoration(labelText: 'Target Dialect'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Any Dialect')),
                    DropdownMenuItem(value: 1, child: Text('Standard Gujarati')),
                    DropdownMenuItem(value: 2, child: Text('Kathiyawadi')),
                    DropdownMenuItem(value: 3, child: Text('Surti')),
                    DropdownMenuItem(value: 4, child: Text('Charotari')),
                    DropdownMenuItem(value: 5, child: Text('Pattani')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedDialectId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedDomain,
                  decoration: const InputDecoration(labelText: 'Domain'),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(value: 'healthcare', child: Text('Healthcare')),
                    DropdownMenuItem(value: 'agriculture', child: Text('Agriculture')),
                    DropdownMenuItem(value: 'education', child: Text('Education')),
                    DropdownMenuItem(value: 'commerce', child: Text('Commerce')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedDomain = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: targetQty.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Target Count'),
                        onChanged: (v) => targetQty = int.tryParse(v) ?? 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: priority.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Priority (1-10)'),
                        onChanged: (v) => priority = (int.tryParse(v) ?? 8).clamp(1, 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                final repo = ref.read(gsipRepositoryProvider);
                final mission = Mission(
                  id: '',
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? 'Targeted collection mission'
                      : descCtrl.text.trim(),
                  taskType: taskType,
                  status: MissionStatus.active,
                  requiredDialectId: selectedDialectId,
                  requiredDomainId: selectedDomain,
                  targetQuantity: targetQty,
                  priority: priority,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                try {
                  await repo.createMission(mission);
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(missionsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mission created successfully!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to create mission: $e')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _startMission(Mission mission) {
    if (widget.profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete your profile first.')),
      );
      return;
    }

    if (mission.taskType == MissionTaskType.recording) {
      // Create a targeted prompt from the mission objective
      final prompt = legacy.Prompt(
        id: 'mission-${mission.id.isNotEmpty ? mission.id : DateTime.now().millisecondsSinceEpoch}',
        textGu: mission.title,
        dialectId: mission.requiredDialectId ?? widget.profile!.nativeDialectId,
        status: 'approved',
      );

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordScreen(
            prompt: prompt,
            profile: widget.profile!,
            missionId: mission.id.isNotEmpty ? mission.id : null,
          ),
        ),
      ).then((_) => ref.invalidate(missionsProvider));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Starting ${mission.taskType.value} workflow.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final missionsAsync = ref.watch(missionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Targeted Missions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Mission',
            onPressed: _openCreateMissionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(missionsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All Tasks'),
                  selected: _selectedTypeFilter == null,
                  onSelected: (_) => setState(() => _selectedTypeFilter = null),
                ),
                const SizedBox(width: 8),
                ...MissionTaskType.values.map((t) {
                  final label = switch (t) {
                    MissionTaskType.recording => '🎙 Recording',
                    MissionTaskType.transcriptionReview => '📝 Review',
                    MissionTaskType.metadataValidation => '🔍 Metadata',
                    MissionTaskType.dialectValidation => '🗣 Dialect',
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: _selectedTypeFilter == t,
                      onSelected: (val) =>
                          setState(() => _selectedTypeFilter = val ? t : null),
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: missionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text('Error loading missions: $err', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () => ref.invalidate(missionsProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (missions) {
                var filtered = missions;
                if (_selectedTypeFilter != null) {
                  filtered = filtered.where((m) => m.taskType == _selectedTypeFilter).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'No active collection missions found.',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Create a targeted mission or trigger one from the Data Coverage Gap Engine.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Create Mission'),
                            onPressed: _openCreateMissionDialog,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final m = filtered[index];
                    final isHighPriority = m.priority >= 8;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isHighPriority
                              ? Colors.deepOrange.shade300
                              : Colors.grey.shade300,
                          width: isHighPriority ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isHighPriority)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.deepOrange.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.deepOrange.shade200),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.local_fire_department, size: 14, color: Colors.deepOrange),
                                        SizedBox(width: 4),
                                        Text(
                                          'High Priority',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.deepOrange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    m.taskType.value.replaceAll('_', ' ').toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                ),
                                const Spacer(),
                                Text(
                                  '${m.completedQuantity} / ${m.targetQuantity}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              m.title,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.description,
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: m.progressFraction,
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade200,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: const Text('Start Task'),
                                  onPressed: () => _startMission(m),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
