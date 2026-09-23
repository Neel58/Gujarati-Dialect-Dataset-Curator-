import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/audio/wav_builder.dart';
import 'package:gujarati_dialect_curator/audio/wav_info.dart';

void main() {
  test('WavBuilder - builds valid WAV from PCM bytes', () {
    // Generate 1 second of fake 16kHz PCM data (16000 samples * 2 bytes = 32000 bytes)
    final pcmData = Uint8List(32000);
    final intData = ByteData.sublistView(pcmData);
    for (int i = 0; i < 16000; i++) {
      intData.setInt16(i * 2, i % 32767, Endian.little);
    }
    
    final wavBytes = buildWav(pcmBytes: pcmData, sampleRate: 16000, channels: 1);
    
    // Total size should be 44 (header) + 32000 (data) = 32044
    expect(wavBytes.length, 32044);
    
    // parseWavHeader should successfully parse it
    final info = parseWavHeader(wavBytes);
    expect(info.sampleRate, 16000);
    expect(info.channels, 1);
    expect(info.durationMs, 1000);
  });
}
