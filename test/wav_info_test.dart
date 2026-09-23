import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/audio/wav_info.dart';

void main() {
  Uint8List buildWav({
    int audioFormat = 1,
    int channels = 1,
    int sampleRate = 16000,
    int bitsPerSample = 16,
    int dataSize = 32000, // 1 second of 16kHz mono 16-bit
  }) {
    final bytes = BytesBuilder();
    // RIFF header
    bytes.add('RIFF'.codeUnits);
    bytes.add([0, 0, 0, 0]); // Chunk size (placeholder)
    bytes.add('WAVE'.codeUnits);
    
    // fmt chunk
    bytes.add('fmt '.codeUnits);
    final fmtData = ByteData(16);
    fmtData.setUint16(0, audioFormat, Endian.little);
    fmtData.setUint16(2, channels, Endian.little);
    fmtData.setUint32(4, sampleRate, Endian.little);
    fmtData.setUint32(8, sampleRate * channels * (bitsPerSample ~/ 8), Endian.little); // Byte rate
    fmtData.setUint16(12, channels * (bitsPerSample ~/ 8), Endian.little); // Block align
    fmtData.setUint16(14, bitsPerSample, Endian.little);
    bytes.add([16, 0, 0, 0]); // fmt chunk size
    bytes.add(fmtData.buffer.asUint8List());

    // data chunk
    bytes.add('data'.codeUnits);
    final dataSizeData = ByteData(4);
    dataSizeData.setUint32(0, dataSize, Endian.little);
    bytes.add(dataSizeData.buffer.asUint8List());
    bytes.add(Uint8List(dataSize)); // Empty data

    return bytes.toBytes();
  }

  group('WavInfo parser', () {
    test('Parses valid 16kHz mono 16-bit WAV', () {
      final wav = buildWav();
      final info = parseWavHeader(wav);
      expect(info.sampleRate, 16000);
      expect(info.channels, 1);
      expect(info.durationMs, 1000);
    });

    test('Throws if wrong sample rate', () {
      final wav = buildWav(sampleRate: 44100);
      expect(() => parseWavHeader(wav), throwsA(predicate((e) => e.toString().contains('Must be 16000 Hz'))));
    });

    test('Throws if stereo', () {
      final wav = buildWav(channels: 2);
      expect(() => parseWavHeader(wav), throwsA(predicate((e) => e.toString().contains('Must be mono (1 channel)'))));
    });

    test('Throws if not 16-bit', () {
      final wav = buildWav(bitsPerSample: 8);
      expect(() => parseWavHeader(wav), throwsA(predicate((e) => e.toString().contains('Must be 16-bit'))));
    });

    test('Throws if truncated', () {
      final wav = buildWav().sublist(0, 20); // Cut before format
      expect(() => parseWavHeader(wav), throwsException);
    });

    test('Throws if not WAVE', () {
      final bytes = BytesBuilder();
      bytes.add('RIFF'.codeUnits);
      bytes.add([0, 0, 0, 0]);
      bytes.add('MP3 '.codeUnits);
      bytes.add(Uint8List(40));
      expect(() => parseWavHeader(bytes.toBytes()), throwsA(predicate((e) => e.toString().contains('Not a WAVE file'))));
    });
  });
}
