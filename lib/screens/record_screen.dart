import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../audio/wav_recorder.dart';
import '../audio/wav_info.dart';
import 'onboarding_screen.dart'; // for providers

class RecordScreen extends ConsumerStatefulWidget {
  final Prompt prompt;
  final Profile profile;
  
  const RecordScreen({
    super.key, 
    required this.prompt,
    required this.profile,
  });

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

enum RecordState { idle, recording, recorded, uploading }

class _RecordScreenState extends ConsumerState<RecordScreen> {
  final WavRecorder _recorder = WavRecorder();
  RecordState _state = RecordState.idle;
  String? _recordedPath;
  WavInfo? _wavInfo;

  // Dropdown states
  Dialect? _selectedDialect;
  District? _selectedDistrict;
  final _otherDialectCtrl = TextEditingController();

  StreamSubscription<Amplitude>? _ampSub;
  double _currentAmplitude = -160.0;
  Timer? _stopTimer;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    // Default to profile values
    // This will be set once providers load in build
  }

  @override
  void dispose() {
    _cleanupTempFile();
    _ampSub?.cancel();
    _stopTimer?.cancel();
    _recorder.dispose();
    _otherDialectCtrl.dispose();
    super.dispose();
  }

  void _cleanupTempFile() {
    if (kIsWeb) return;
    if (_recordedPath != null) {
      try {
        final file = io.File(_recordedPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _showSnack('Microphone permission is required.');
        return;
      }
      
      _cleanupTempFile();
      _wavInfo = null;

      final path = await _recorder.start();
      
      setState(() {
        _state = RecordState.recording;
        _recordedPath = path;
        _startTime = DateTime.now();
      });

      _ampSub = _recorder.onAmplitudeChanged.listen((amp) {
        setState(() => _currentAmplitude = amp.current);
      });

      _stopTimer = Timer(const Duration(seconds: 30), () {
        if (_state == RecordState.recording) {
          _stopRecording();
          _showSnack('Auto-stopped at 30 seconds.');
        }
      });
    } catch (e) {
      _showSnack('Start error: $e');
      setState(() => _state = RecordState.idle);
    }
  }

  Future<void> _stopRecording() async {
    _stopTimer?.cancel();
    _ampSub?.cancel();
    try {
      final path = await _recorder.stop();
      if (path == null) {
        _showSnack('Error: No audio returned.');
        setState(() => _state = RecordState.idle);
        return;
      }

      final duration = DateTime.now().difference(_startTime!);
      if (duration.inSeconds < 1) {
        _showSnack('Recording too short (minimum 1 second).');
        _cleanupTempFile();
        setState(() => _state = RecordState.idle);
        return;
      }

      // Parse WAV Header
      if (!kIsWeb) {
        final bytes = await io.File(path).readAsBytes();
        try {
          _wavInfo = parseWavHeader(bytes);
        } catch (e) {
          _showSnack('Audio validation failed: $e');
          _cleanupTempFile();
          setState(() => _state = RecordState.idle);
          return;
        }
      } else {
        // Mock info for web since it might be webm/opus
        _wavInfo = WavInfo(durationMs: duration.inMilliseconds, sampleRate: 16000, channels: 1);
      }

      setState(() {
        _state = RecordState.recorded;
        _recordedPath = path;
      });
    } catch (e) {
      _showSnack('Stop error: $e');
      setState(() => _state = RecordState.idle);
    }
  }

  Future<void> _submit() async {
    if (_state != RecordState.recorded || _recordedPath == null) return;
    
    if (_selectedDialect == null || _selectedDistrict == null) {
      _showSnack('Please select a dialect and district.');
      return;
    }
    if (_selectedDialect!.slug == 'other' && _otherDialectCtrl.text.trim().isEmpty) {
      _showSnack('Please specify the other dialect.');
      return;
    }

    setState(() => _state = RecordState.uploading);
    try {
      Uint8List fileBytes;
      String contentType = 'audio/wav';
      String ext = '.wav';

      if (kIsWeb) {
        final res = await http.get(Uri.parse(_recordedPath!));
        fileBytes = res.bodyBytes;
        // Spoof as mp4 to bypass strict Supabase bucket constraints on web.
        // Chrome will mime-sniff the underlying WebM bytes and play it perfectly.
        contentType = 'audio/mp4';
        ext = '.mp4';
      } else {
        fileBytes = await io.File(_recordedPath!).readAsBytes();
      }
      
      final uuid = const Uuid().v4();
      final storagePath = '${widget.profile.id}/$uuid$ext';

      // 1. Upload file
      await Supabase.instance.client.storage.from('audio-clips').uploadBinary(
        storagePath,
        fileBytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: false,
        ),
      );

      // 2. Insert row
      final recording = Recording(
        id: uuid,
        userId: widget.profile.id,
        promptId: widget.prompt.id,
        promptText: widget.prompt.textGu,
        dialectId: _selectedDialect!.id,
        dialectOtherText: _selectedDialect!.slug == 'other' ? _otherDialectCtrl.text.trim() : null,
        districtId: _selectedDistrict!.id,
        durationMs: _wavInfo!.durationMs,
        sampleRate: _wavInfo!.sampleRate,
        channels: _wavInfo!.channels,
        audioFormat: 'wav',
        storagePath: storagePath,
        createdAt: DateTime.now(),
      );

      try {
        await Supabase.instance.client.from('recordings').insert(recording.toJson());
      } catch (e) {
        // If row insert fails, delete uploaded object
        await Supabase.instance.client.storage.from('audio-clips').remove([storagePath]);
        throw Exception('Database insert failed: $e. Audio kept locally for retry.');
      }

      // Success
      _cleanupTempFile();
      if (!mounted) return;
      _showSnack('Uploaded successfully.');
      Navigator.of(context).pop();
    } catch (e) {
      _showSnack(e.toString());
      setState(() => _state = RecordState.recorded);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final dialectsAsync = ref.watch(dialectsProvider);
    final districtsAsync = ref.watch(districtsProvider);

    // Initial pre-fill
    dialectsAsync.whenData((dialects) {
      if (_selectedDialect == null && dialects.isNotEmpty) {
        _selectedDialect = dialects.firstWhere(
          (d) => d.id == widget.profile.nativeDialectId,
          orElse: () => dialects.first,
        );
      }
    });
    districtsAsync.whenData((districts) {
      if (_selectedDistrict == null && districts.isNotEmpty) {
        _selectedDistrict = districts.firstWhere(
          (d) => d.id == widget.profile.grewUpDistrictId,
          orElse: () => districts.first,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Record Prompt')),
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
                  widget.prompt.textGu,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Dropdowns
            dialectsAsync.when(
              data: (dialects) => DropdownButtonFormField<Dialect>(
                decoration: const InputDecoration(labelText: 'Dialect for this recording'),
                initialValue: _selectedDialect,
                items: dialects.map((d) => DropdownMenuItem(
                  value: d, 
                  child: Text('${d.nameEn} - ${d.nameGu}'),
                )).toList(),
                onChanged: _state == RecordState.uploading 
                    ? null 
                    : (v) => setState(() => _selectedDialect = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading dialects'),
            ),
            if (_selectedDialect?.slug == 'other') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _otherDialectCtrl,
                decoration: const InputDecoration(labelText: 'Specify other dialect'),
                enabled: _state != RecordState.uploading,
              ),
            ],
            const SizedBox(height: 16),
            districtsAsync.when(
              data: (districts) => DropdownButtonFormField<District>(
                decoration: const InputDecoration(labelText: 'Recording location (District)'),
                initialValue: _selectedDistrict,
                items: districts.map((d) => DropdownMenuItem(
                  value: d,
                  child: Text(d.nameGu != null ? '${d.nameEn} (${d.nameGu})' : d.nameEn),
                )).toList(),
                onChanged: _state == RecordState.uploading
                    ? null
                    : (v) => setState(() => _selectedDistrict = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading districts'),
            ),

            const SizedBox(height: 40),
            _buildRecordButton(),
            const SizedBox(height: 40),
            if (_state == RecordState.recorded || _state == RecordState.uploading)
              FilledButton(
                onPressed: _state == RecordState.uploading ? null : _submit,
                child: _state == RecordState.uploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Recording'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    double level = (_currentAmplitude + 160) / 160.0;
    level = level.clamp(0.0, 1.0);

    return Column(
      children: [
        if (_state == RecordState.recording)
          Container(
            height: 10,
            width: 100,
            margin: const EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(value: level, backgroundColor: Colors.grey[300]),
          ),
        IconButton(
          iconSize: 72,
          icon: Icon(
            _state == RecordState.recording ? Icons.stop_circle : Icons.mic,
            color: _state == RecordState.recording ? Colors.red : Colors.deepPurple,
          ),
          onPressed: _state == RecordState.uploading 
              ? null 
              : (_state == RecordState.recording ? _stopRecording : _startRecording),
        ),
        Text(_state == RecordState.recording
            ? 'Recording... tap to stop'
            : (_state == RecordState.recorded
                ? 'Recorded — tap mic to retake'
                : 'Tap to record (up to 30s)')),
      ],
    );
  }
}