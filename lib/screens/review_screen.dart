import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/supabase_service.dart';
import '../models/recording_entry.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final AudioPlayer _player = AudioPlayer();
  late Future<List<RecordingEntry>> _future;
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _future = SupabaseService.instance.fetchRecordings();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(String storagePath) async {
    if (_playingPath == storagePath) {
      await _player.stop();
      setState(() => _playingPath = null);
      return;
    }
    final url = SupabaseService.instance.publicUrlFor(storagePath);
    await _player.play(UrlSource(url));
    setState(() => _playingPath = storagePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uploaded recordings')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _future = SupabaseService.instance.fetchRecordings();
          });
          await _future;
        },
        child: FutureBuilder<List<RecordingEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                ),
              );
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const Center(child: Text('No recordings yet.'));
            }
            return ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final storagePath = row.storagePath;
                final isPlaying = _playingPath == storagePath;
                return ListTile(
                  title: Text(row.prompt),
                  subtitle: Text(
                    '${row.speakerName} · ${row.speakerAge} · '
                    '${row.speakerPlace} · ${row.speakerDialect}',
                  ),
                  trailing: IconButton(
                    icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                    onPressed: () => _togglePlay(storagePath),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}