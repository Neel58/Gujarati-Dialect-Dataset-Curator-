import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'review_screen.dart';
import 'record_screen.dart';
import 'onboarding_screen.dart'; // for dialect provider
import 'add_prompt_screen.dart';

final promptsProvider = FutureProvider<List<Prompt>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  
  final data = await Supabase.instance.client
      .from('prompts')
      .select()
      .eq('status', 'approved');
      
  final prompts = data.map((json) => Prompt.fromJson(json)).toList();
  
  if (user != null) {
    final recordedData = await Supabase.instance.client
        .from('recordings')
        .select('prompt_id')
        .eq('user_id', user.id);
        
    final recordedIds = recordedData.map((e) => e['prompt_id'] as int).toSet();
    
    // Sort: unrecorded first
    prompts.sort((a, b) {
      final aRecorded = recordedIds.contains(a.id);
      final bRecorded = recordedIds.contains(b.id);
      if (aRecorded == bRecorded) return a.id.compareTo(b.id);
      return aRecorded ? 1 : -1;
    });
  }
  
  return prompts;
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int? _selectedDialectFilter;
  Profile? _cachedProfile;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final data = await Supabase.instance.client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (data != null && mounted) {
      setState(() {
        _cachedProfile = Profile.fromJson(data);
      });
    }
  }

  void _editProfile(BuildContext context) {
    if (_cachedProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile loading...')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OnboardingScreen(currentProfile: _cachedProfile!)),
    ).then((_) => _fetchProfile());
  }
  
  void _reportPrompt(Prompt prompt) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      await Supabase.instance.client.from('prompt_reports').insert({
        'prompt_id': prompt.id,
        'reporter_id': user.id,
        'reason': 'Flagged by user',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prompt reported.')));
      ref.invalidate(promptsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to report: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final promptsAsync = ref.watch(promptsProvider);
    final dialectsAsync = ref.watch(dialectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gujarati Dialect Curator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Edit Profile',
            onPressed: () => _editProfile(context),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'My Uploads',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReviewScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          if (_cachedProfile == null) return;
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddPromptScreen(profile: _cachedProfile!)),
          );
          ref.invalidate(promptsProvider);
        },
      ),
      body: Column(
        children: [
          dialectsAsync.when(
            data: (dialects) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedDialectFilter == null,
                    onSelected: (val) => setState(() => _selectedDialectFilter = null),
                  ),
                  const SizedBox(width: 8),
                  ...dialects.map((d) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(d.nameEn),
                      selected: _selectedDialectFilter == d.id,
                      onSelected: (val) => setState(() => _selectedDialectFilter = val ? d.id : null),
                    ),
                  )),
                ],
              ),
            ),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
          Expanded(
            child: promptsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error loading prompts: $err'),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(promptsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (prompts) {
                var filtered = prompts;
                if (_selectedDialectFilter != null) {
                  filtered = filtered.where((p) => p.dialectId == _selectedDialectFilter).toList();
                }
                
                if (filtered.isEmpty) {
                  return const Center(child: Text('No prompts available.'));
                }
                
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(promptsProvider);
                    await ref.read(promptsProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final prompt = filtered[index];
                      
                      String dialectName = '';
                      dialectsAsync.whenData((dialects) {
                        final d = dialects.where((e) => e.id == prompt.dialectId).firstOrNull;
                        if (d != null) dialectName = d.nameEn;
                      });

                      return Card(
                        child: ListTile(
                          title: Text(prompt.textGu, style: const TextStyle(fontSize: 18)),
                          subtitle: dialectName.isNotEmpty ? Text(dialectName) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.mic, color: Colors.deepPurple),
                                onPressed: () {
                                  if (_cachedProfile == null) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RecordScreen(prompt: prompt, profile: _cachedProfile!),
                                    ),
                                  );
                                },
                              ),
                              PopupMenuButton<String>(
                                onSelected: (val) {
                                  if (val == 'report') _reportPrompt(prompt);
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'report',
                                    child: Text('Report Prompt'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}