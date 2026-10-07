import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/audio/wav_builder.dart';
import 'package:gujarati_dialect_curator/services/quality_engine.dart';

void main() {
  group('QualityEngine - Real Audio Quality Computation', () {
    test('Valid 16kHz mono 16-bit WAV computes expected quality scores & explanations', () {
      // Create 1 second of silence / low tone at 16kHz mono (16,000 samples = 32,000 bytes)
      final pcm = Uint8List(32000);
      final wav = buildWav(
        pcmBytes: pcm,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );

      final analysis = QualityEngine.analyze(
        wavBytes: wav,
        hasTranscript: true,
        hasDialect: true,
        hasDistrict: true,
        consentType: 'commercial_ai',
      );

      expect(analysis.formatValid, isTrue);
      expect(analysis.sampleRateHz, equals(16000));
      expect(analysis.channels, equals(1));
      expect(analysis.bitDepth, equals(16));
      expect(analysis.durationMs, equals(1000));
      expect(analysis.audioSha256, isNotNull);
      expect(analysis.audioSha256!.length, equals(64)); // SHA-256 hex string

      // Audio quality score must be calculated (not null)
      expect(analysis.audioQualityScore, isNotNull);
      expect(analysis.overallQualityScore, isNotNull);
      expect(analysis.metadataQualityScore, equals(100)); // all metadata provided
      expect(analysis.consentQualityScore, equals(85)); // commercial_ai gives 85, open gives 100

      // Explanations must be explainable items
      expect(analysis.qualityExplanation.isNotEmpty, isTrue);
      expect(
        analysis.qualityExplanation.any((e) => e.check == 'format_valid' && e.passed),
        isTrue,
      );
      expect(
        analysis.qualityExplanation.any((e) => e.check == 'sample_rate' && e.passed),
        isTrue,
      );

      // Human-readable report should exist and be descriptive
      expect(analysis.humanReadableReport.contains('Quality Report'), isTrue);
    });

    test('Invalid bytes fail format_valid check gracefully', () {
      final corruptBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      final analysis = QualityEngine.analyze(
        wavBytes: corruptBytes,
      );

      expect(analysis.formatValid, isFalse);
      expect(analysis.audioQualityScore, equals(0));
      expect(
        analysis.qualityExplanation.any((e) => e.check == 'format_valid' && !e.passed),
        isTrue,
      );
    });
  });
}
