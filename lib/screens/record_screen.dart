import 'dart:io' as io;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../audio/wav_recorder.dart';
import '../audio/wav_info.dart';
import '../data/repositories/gsip_repository.dart';
import '../services/quality_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'onboarding_screen.dart'; // for providers

class RecordScreen extends ConsumerStatefulWidget {
  final Prompt prompt;
  final Profile profile;
  final String? missionId;
  
  const RecordScreen({
    super.key, 
    required this.prompt,
    required this.profile,
    this.missionId,
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

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

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
    _player.dispose();
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
      Uint8List bytes;
      if (!kIsWeb) {
        bytes = await io.File(path).readAsBytes();
      } else {
        bytes = _recorder.webWavBytes!;
      }
      
      try {
        _wavInfo = parseWavHeader(bytes);
      } catch (e) {
        _showSnack('Audio validation failed: $e');
        _cleanupTempFile();
        setState(() => _state = RecordState.idle);
        return;
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
      final fileBytes = kIsWeb ? _recorder.webWavBytes! : await io.File(_recordedPath!).readAsBytes();
      
      bool qualitySubmissionFailed = false;
      QualityAnalysis? qualityAnalysis;
      try {
        qualityAnalysis = QualityEngine.analyze(
          wavBytes: fileBytes,
          hasTranscript: widget.prompt.textGu.isNotEmpty,
          hasDialect: true,
          hasDistrict: true,
          consentType: 'research_only',
        );

        final qa = qualityAnalysis;
        final isBadAudio = qa.speechPresence == false || 
                           (qa.silenceRatio ?? 0) > 0.7 || 
                           (qa.audioQualityScore ?? 100) < 50;

        if (isBadAudio) {
          final shouldProceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Low Quality Audio Detected'),
              content: Text('Audio score: ${qa.audioQualityScore}/100.\nThis audio might be too quiet, noisy, or clipped. Would you like to retake it or submit anyway?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retake')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit Anyway')),
              ],
            ),
          );
          if (shouldProceed != true) {
            setState(() => _state = RecordState.recorded);
            return;
          }
        }
      } catch (e) {
        debugPrint('Local quality analysis failed: $e');
        qualitySubmissionFailed = true;
      }

      final uuid = const Uuid().v4();
      final storagePath = '${widget.profile.id}/$uuid.wav';

      // 1. Upload file
      await Supabase.instance.client.storage.from('audio-clips').uploadBinary(
        storagePath,
        fileBytes,
        fileOptions: const FileOptions(
          contentType: 'audio/wav',
          upsert: false,
        ),
      );

      // 2. Insert row
      final recording = Recording(
        id: uuid,
        userId: widget.profile.id,
        promptId: widget.missionId != null ? null : widget.prompt.id,
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

        // Canonical DataAsset creation with automated quality analysis
        try {
          final asset = await GsipRepository().createDataAsset(
            recordingId: uuid,
            transcript: widget.prompt.textGu,
            dialectId: _selectedDialect?.id,
            domainId: 'general',
            durationMs: _wavInfo?.durationMs,
            sampleRate: _wavInfo?.sampleRate,
            channels: _wavInfo?.channels,
            fileSizeBytes: fileBytes.length,
            audioFormat: 'wav',
            storagePath: storagePath,
            consentTypeId: 'research_only',
            qualityAnalysis: qualityAnalysis,
          );

          if (widget.missionId != null) {
            await GsipRepository().submitToMission(
              missionId: widget.missionId!,
              dataAssetId: asset.id,
            );
          }
        } catch (assetErr) {
          debugPrint('Notice: Canonical data_asset creation/submission result: $assetErr');
          qualitySubmissionFailed = true;
        }
      } catch (e) {
        // If row insert fails, delete uploaded object
        await Supabase.instance.client.storage.from('audio-clips').remove([storagePath]);
        throw Exception('Database insert failed: $e. Audio kept locally for retry.');
      }

      // Success
      _cleanupTempFile();
      if (!mounted) return;
      
      if (qualitySubmissionFailed) {
        _showSnack('Uploaded, but quality check couldn\'t run.');
        Navigator.of(context).pop();
      } else if (qualityAnalysis != null) {
        showModalBottomSheet(
          context: context,
          isDismissible: false,
          enableDrag: false,
          builder: (ctx) => Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Uploaded successfully!', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text('Quality Score: ${qualityAnalysis!.overallQualityScore}/100', 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                ...(() {
                  final exps = qualityAnalysis!.qualityExplanation;
                  final important = exps.where((e) => 
                    !e.passed || 
                    e.message.toLowerCase().contains('speech') || 
                    e.message.toLowerCase().contains('silence') || 
                    e.message.toLowerCase().contains('volume') || 
                    e.message.toLowerCase().contains('clip')
                  ).toList();
                  return important.isNotEmpty ? important.take(4) : exps.take(4);
                }()).map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(e.passed ? Icons.check_circle : Icons.warning, 
                          color: e.passed ? Colors.green : Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.message)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ).then((_) {
          if (mounted) Navigator.of(context).pop();
        });
      } else {
        _showSnack('Uploaded successfully.');
        Navigator.of(context).pop();
      }

    } catch (e) {
      _showSnack(e.toString());
      setState(() => _state = RecordState.recorded);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
    } else {
      try {
        if (kIsWeb) {
          await _player.play(BytesSource(_recorder.webWavBytes!));
        } else {
          await _player.play(DeviceFileSource(_recordedPath!));
        }
        setState(() => _isPlaying = true);
        _player.onPlayerComplete.first.then((_) {
          if (mounted) setState(() => _isPlaying = false);
        });
      } catch (e) {
        _showSnack('Play error: $e');
        setState(() => _isPlaying = false);
      }
    }
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
              error: (_, _) => const Text('Error loading dialects'),
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
              error: (_, _) => const Text('Error loading districts'),
            ),

            const SizedBox(height: 40),
            _buildRecordButton(),
            const SizedBox(height: 40),
            if (_state == RecordState.recorded || _state == RecordState.uploading)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                    iconSize: 48,
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _state == RecordState.uploading ? null : _togglePlay,
                  ),
                  const SizedBox(width: 20),
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