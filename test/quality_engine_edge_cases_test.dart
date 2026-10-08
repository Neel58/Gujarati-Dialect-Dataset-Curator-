import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/audio/wav_builder.dart';
import 'package:gujarati_dialect_curator/services/quality_engine.dart';

void main() {
  group('QualityEngine Edge Cases & Deterministic Signal Verification', () {
    test('Clipping detection: detects digital clipping when samples reach maximum amplitude', () {
      // 1 second of 16kHz mono audio (16,000 samples)
      final pcm = Uint8List(32000);
      final bd = ByteData.sublistView(pcm);

      // Insert samples that clip at 32767
      for (int i = 0; i < 16000; i++) {
        bd.setInt16(i * 2, i < 500 ? 32767 : 5000, Endian.little);
      }

      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);
      final analysis = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasTranscript: true,
        hasDialect: true,
        hasDistrict: true,
        consentType: 'commercial_ai',
      );

      expect(analysis.clippingDetected, isTrue);
      expect(
        analysis.qualityExplanation.any((e) => e.check == 'clipping' && !e.passed),
        isTrue,
        reason: 'Should explain that audio clipping was detected',
      );
    });

    test('Clean volume: moderate amplitude audio does not flag clipping', () {
      final pcm = Uint8List(32000);
      final bd = ByteData.sublistView(pcm);

      for (int i = 0; i < 16000; i++) {
        bd.setInt16(i * 2, 8000, Endian.little);
      }

      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);
      final analysis = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasTranscript: true,
        hasDialect: true,
        hasDistrict: true,
      );

      expect(analysis.clippingDetected, isFalse);
      expect(
        analysis.qualityExplanation.any((e) => e.check == 'clipping' && e.passed),
        isTrue,
      );
    });

    test('Silence ratio: 100% silent audio results in silence_ratio=1.0 and speech_presence=false', () {
      // Completely zeroed PCM
      final pcm = Uint8List(32000);
      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);

      final analysis = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasTranscript: true,
        hasDialect: true,
        hasDistrict: true,
      );

      expect(analysis.silenceRatio, equals(1.0));
      expect(analysis.speechPresence, isFalse);
      expect(
        analysis.qualityExplanation.any((e) => e.check == 'speech_presence' && !e.passed),
        isTrue,
      );
    });

    test('Speech presence: active audio results in low silence ratio and speech_presence=true', () {
      final pcm = Uint8List(32000);
      final bd = ByteData.sublistView(pcm);

      // Active voice pattern (amplitude > 500 across frames)
      for (int i = 0; i < 16000; i++) {
        bd.setInt16(i * 2, (i % 2 == 0 ? 4000 : -4000), Endian.little);
      }

      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);
      final analysis = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasTranscript: true,
        hasDialect: true,
        hasDistrict: true,
      );

      expect(analysis.silenceRatio, lessThan(0.5));
      expect(analysis.speechPresence, isTrue);
      expect(
        analysis.qualityExplanation.any((e) => e.check == 'speech_presence' && e.passed),
        isTrue,
      );
    });

    test('Consent quality scores: correctly scores open, commercial_ai, research_only, and custom', () {
      final pcm = Uint8List(32000);
      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);

      final openAnalysis = QualityEngine.analyze(wavBytes: wavBytes, consentType: 'open');
      final commercialAnalysis = QualityEngine.analyze(wavBytes: wavBytes, consentType: 'commercial_ai');
      final researchAnalysis = QualityEngine.analyze(wavBytes: wavBytes, consentType: 'research_only');
      final unknownAnalysis = QualityEngine.analyze(wavBytes: wavBytes, consentType: 'other_custom');

      expect(openAnalysis.consentQualityScore, equals(100));
      expect(commercialAnalysis.consentQualityScore, equals(85));
      expect(researchAnalysis.consentQualityScore, equals(70));
      expect(unknownAnalysis.consentQualityScore, equals(50));
    });

    test('Metadata quality scoring: reflects presence/absence of dialect, district, and transcript', () {
      final pcm = Uint8List(32000);
      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);

      final fullMeta = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasDialect: true,
        hasDistrict: true,
        hasTranscript: true,
      );
      expect(fullMeta.metadataQualityScore, equals(100)); // 60 + 20 + 15 + 5

      final noMeta = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasDialect: false,
        hasDistrict: false,
        hasTranscript: false,
      );
      expect(noMeta.metadataQualityScore, equals(60)); // base 60

      final partialMeta = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasDialect: true,
        hasDistrict: false,
        hasTranscript: false,
      );
      expect(partialMeta.metadataQualityScore, equals(80)); // 60 + 20
    });

    test('Overall quality score floor masks complete silence, necessitating independent audio checks', () {
      // 3 seconds of total silence (zeroes)
      final pcm = Uint8List(16000 * 2 * 3);
      final wavBytes = buildWav(pcmBytes: pcm, sampleRate: 16000, channels: 1);

      final analysis = QualityEngine.analyze(
        wavBytes: wavBytes,
        hasTranscript: true,
        hasDialect: true,
        hasDistrict: true,
        consentType: 'research_only',
      );

      // Confirm audio is flagged as completely bad
      expect(analysis.speechPresence, isFalse);
      expect(analysis.silenceRatio, greaterThan(0.9));
      expect(analysis.audioQualityScore, lessThan(50));

      // Confirm overall score still passes due to the blended floor!
      // (100 metadata * 0.25) + (70 consent * 0.15) = 35.5
      // Plus audio score of ~40 * 0.6 = 24.
      // Total = ~60. This proves why pre-upload gate must check audioQualityScore directly.
      expect(analysis.overallQualityScore, greaterThanOrEqualTo(50));

      // This boolean logic matches the fix in record_screen.dart
      final isBadAudio = analysis.speechPresence == false || 
                         (analysis.silenceRatio ?? 0) > 0.7 || 
                         (analysis.audioQualityScore ?? 100) < 50;
                         
      expect(isBadAudio, isTrue);
    });
  });
}
