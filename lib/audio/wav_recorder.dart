import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'sample_rate_helper.dart';
import 'resampler.dart';
import 'wav_builder.dart';

class WavRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  
  // Web specific state
  BytesBuilder? _webBytesBuilder;
  StreamSubscription<Uint8List>? _webStreamSub;
  Uint8List? webWavBytes;
  DateTime? _webStartTime;
  double _webMaxAmplitude = -160.0;
  Timer? _webAmpTimer;
  final StreamController<Amplitude> _webAmpController = StreamController<Amplitude>.broadcast();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<String> start() async {
    webWavBytes = null;
    _webMaxAmplitude = -160.0;

    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    } else {
      _path = ''; // path is ignored on web
    }

    if (kIsWeb) {
      _webBytesBuilder = BytesBuilder();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      
      _webStartTime = DateTime.now();
      _webStreamSub = stream.listen((data) {
        _webBytesBuilder!.add(data);
        _calculateWebAmplitude(data);
      });
      
      // Start fake amplitude timer to match mobile behavior
      _webAmpTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!_webAmpController.isClosed) {
          _webAmpController.add(Amplitude(current: _webMaxAmplitude, max: 0.0));
          // decay slightly for visual effect if no new loud samples come in
          _webMaxAmplitude = max(-160.0, _webMaxAmplitude - 5.0);
        }
      });
      
    } else {
      bool useWav = await _recorder.isEncoderSupported(AudioEncoder.wav);
      await _recorder.start(
        RecordConfig(
          encoder: useWav ? AudioEncoder.wav : AudioEncoder.pcm16bits,
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
  
  void _calculateWebAmplitude(Uint8List data) {
    if (data.isEmpty) return;
    final intData = ByteData.sublistView(data);
    double sumSquares = 0;
    int samples = data.length ~/ 2;
    for (int i = 0; i < samples; i++) {
      int sample = intData.getInt16(i * 2, Endian.little);
      sumSquares += sample * sample;
    }
    double rms = sqrt(sumSquares / samples);
    double dbfs = rms > 0 ? 20 * log(rms / 32768.0) / ln10 : -160.0;
    _webMaxAmplitude = max(_webMaxAmplitude, dbfs);
  }

  Future<String?> stop() async {
    if (kIsWeb) {
      final stopTime = DateTime.now();
      await _recorder.stop();
      await _webStreamSub?.cancel();
      _webAmpTimer?.cancel();
      
      final pcmBytes = _webBytesBuilder?.toBytes() ?? Uint8List(0);
      if (pcmBytes.isEmpty) {
        throw Exception("No audio data captured.");
      }
      
      int actualRate = getWebHardwareSampleRate();
      if (actualRate <= 0) {
        // Fallback to timing estimation
        final durationSecs = stopTime.difference(_webStartTime!).inMilliseconds / 1000.0;
        final numSamples = pcmBytes.length / 2;
        final estimatedRate = numSamples / durationSecs;
        
        // Find nearest standard rate
        final standardRates = [16000, 44100, 48000];
        int bestRate = 16000;
        double minDiff = double.infinity;
        
        for (var rate in standardRates) {
          final diff = (estimatedRate - rate).abs() / rate;
          if (diff < minDiff) {
            minDiff = diff;
            bestRate = rate;
          }
        }
        
        if (minDiff <= 0.03) {
          actualRate = bestRate;
        } else {
          throw Exception("Unable to determine sample rate securely. Estimated rate: ${estimatedRate.toStringAsFixed(1)}");
        }
      }
      
      Uint8List finalPcm = pcmBytes;
      if (actualRate != 16000) {
        finalPcm = resamplePcm16(pcmBytes, actualRate, 16000);
      }
      
      webWavBytes = buildWav(pcmBytes: finalPcm, sampleRate: 16000, channels: 1);
      
      return 'memory';
    } else {
      final path = await _recorder.stop();
      return path ?? _path;
    }
  }

  Stream<Amplitude> get onAmplitudeChanged => kIsWeb ? _webAmpController.stream : _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  void dispose() {
    _webStreamSub?.cancel();
    _webAmpTimer?.cancel();
    _webAmpController.close();
    _recorder.dispose();
  }
}
