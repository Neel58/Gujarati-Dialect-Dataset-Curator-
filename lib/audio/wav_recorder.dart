import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class WavRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<String> start() async {
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';

    // We only use standard record plugin for now, and fallback logic if encoder is unsupported.
    // For web, wav isn't always supported natively by MediaRecorder, but we will try.
    bool useWav = false;
    if (!kIsWeb) {
      useWav = await _recorder.isEncoderSupported(AudioEncoder.wav);
    }

    if (useWav) {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: _path!,
      );
    } else {
      // Fallback: PCM 16 bit
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: _path!,
      );
    }
    return _path!;
  }

  Future<String?> stop() async {
    final path = await _recorder.stop();
    if (path != null && !kIsWeb) {
      // If we fell back to PCM, we might need to prepend WAV header.
      // But the record plugin actually writes a wav header when using pcm16bits to a file on iOS/Android.
      // However, we will verify and rewrite header if necessary in the parsing step.
    }
    return path ?? _path;
  }

  Stream<Amplitude> get onAmplitudeChanged => _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  void dispose() {
    _recorder.dispose();
  }
}
