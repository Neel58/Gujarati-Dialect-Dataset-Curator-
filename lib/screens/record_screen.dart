import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/supabase_service.dart';
import '../models/contributor.dart';

class RecordScreen extends StatefulWidget {
  final String prompt;
  final Contributor speaker;
  
  const RecordScreen({
    super.key, 
    required this.prompt,
    required this.speaker,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploading = false;
  String? _recordedPath;

  @override
  void dispose() {
    _cleanupTempFile();
    _recorder.dispose();
    super.dispose();
  }

  void _cleanupTempFile() {
    if (_recordedPath != null) {
      final file = File(_recordedPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showSnack('Microphone permission is required to record.');
      // Ideally show a button to open App Settings if permanently denied
      return;
    }

    // Clean up any previous recording
    _cleanupTempFile();

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordedPath = path;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _recordedPath = path ?? _recordedPath;
    });
  }

  Future<void> _submit() async {
    if (_isUploading) return; // Prevent double-submit race condition
    if (_recordedPath == null) {
      _showSnack('Record audio before submitting.');
      return;
    }

    setState(() => _isUploading = true);
    try {
      await SupabaseService.instance.uploadRecording(
        audioFile: File(_recordedPath!),
        prompt: widget.prompt,
        speaker: widget.speaker,
      );
      if (!mounted) return;
      _showSnack('Uploaded successfully.');
      Navigator.of(context).pop();
    } catch (e) {
      _showSnack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record entry')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.prompt,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Speaker: ${widget.speaker.name}',
              style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _buildRecordButton(),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _isUploading ? null : _submit,
              child: _isUploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    return Column(
      children: [
        IconButton(
          iconSize: 72,
          icon: Icon(
            _isRecording ? Icons.stop_circle : Icons.mic,
            color: _isRecording ? Colors.red : Colors.deepPurple,
          ),
          onPressed: _isRecording ? _stopRecording : _startRecording,
        ),
        Text(_isRecording
            ? 'Recording... tap to stop'
            : (_recordedPath != null
                ? 'Recorded — tap to re-record'
                : 'Tap to record')),
      ],
    );
  }
}