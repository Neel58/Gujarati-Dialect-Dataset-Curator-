import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import 'onboarding_screen.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final AudioPlayer _player = AudioPlayer();
  List<Recording> _recordings = [];
  bool _isLoading = true;
  String? _error;
  String? _playingPath;
  
  bool _isAdmin = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _checkAdminAndFetch();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _checkAdminAndFetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profileData = await Supabase.instance.client
            .from('profiles')
            .select('is_admin')
            .eq('id', user.id)
            .maybeSingle();
        if (profileData != null) {
          _isAdmin = profileData['is_admin'] == true;
        }
      }
      await _fetchRecordings();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchRecordings() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      var query = Supabase.instance.client
          .from('recordings')
          .select();

      if (!_showAll) {
        query = query.eq('user_id', user.id);
      }

      final data = await query.order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _recordings = data.map((json) => Recording.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePlay(String storagePath) async {
    if (_playingPath == storagePath) {
      await _player.stop();
      setState(() => _playingPath = null);
      return;
    }
    
    try {
      final url = await Supabase.instance.client.storage
          .from('audio-clips')
          .createSignedUrl(storagePath, 3600); // 1 hour
      
      await _player.play(UrlSource(url));
      setState(() => _playingPath = storagePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Play error: $e')));
    }
  }

  Future<void> _deleteRecording(Recording r) async {
    try {
      // Delete storage object first
      await Supabase.instance.client.storage.from('audio-clips').remove([r.storagePath]);
      // Then delete row
      await Supabase.instance.client.from('recordings').delete().eq('id', r.id);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted successfully')));
      _fetchRecordings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialectsAsync = ref.watch(dialectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Uploads'),
        actions: [
          if (_isAdmin)
            Row(
              children: [
                const Text('All'),
                Switch(
                  value: _showAll,
                  onChanged: (val) {
                    setState(() {
                      _showAll = val;
                      _isLoading = true;
                    });
                    _fetchRecordings();
                  },
                ),
              ],
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _recordings.isEmpty
                  ? const Center(child: Text('No recordings found.'))
                  : RefreshIndicator(
                      onRefresh: _fetchRecordings,
                      child: ListView.builder(
                        itemCount: _recordings.length,
                        itemBuilder: (context, index) {
                          final r = _recordings[index];
                          final isPlaying = _playingPath == r.storagePath;
                          
                          // Format date
                          final dateStr = '${r.createdAt.year}-${r.createdAt.month.toString().padLeft(2, '0')}-${r.createdAt.day.toString().padLeft(2, '0')}';
                          final durStr = '${(r.durationMs / 1000).toStringAsFixed(1)}s';
                          
                          String dialectName = '';
                          dialectsAsync.whenData((dialects) {
                            final d = dialects.where((e) => e.id == r.dialectId).firstOrNull;
                            if (d != null) dialectName = d.nameEn;
                          });
                          
                          if (r.dialectOtherText != null) {
                            dialectName += ' (${r.dialectOtherText})';
                          }

                          return ListTile(
                            title: Text(r.promptText ?? r.promptId ?? 'Legacy Prompt'),
                            subtitle: Text('$dialectName · $durStr · $dateStr'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                                  onPressed: () => _togglePlay(r.storagePath),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Delete?'),
                                        content: const Text('Are you sure you want to delete this recording?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      _deleteRecording(r);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}