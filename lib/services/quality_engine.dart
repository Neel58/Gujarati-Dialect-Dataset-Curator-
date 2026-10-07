import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../audio/wav_info.dart';
import '../models/gsip_models.dart';

/// QualityEngine computes real quality signals from audio bytes and metadata.
///
/// IMPORTANT: This class ONLY computes signals that can be derived from the
/// raw audio bytes and WAV header. Signals that require ML models
/// (e.g., true speech activity detection, SNR estimation, speaker verification)
/// are explicitly marked as UNAVAILABLE rather than fabricated.
class QualityEngine {
  /// Analyze a WAV audio file and compute quality signals.
  ///
  /// [wavBytes]    - the raw WAV file bytes
  /// [hasTranscript] - whether a transcript has been provided
  /// [hasDialect]  - whether a dialect has been specified
  /// [hasDistrict] - whether a district/location has been specified
  /// [consentType] - the consent type ID
  ///
  /// Returns a [QualityAnalysis] with real computed values.
  /// Never returns fabricated or random values.
  static QualityAnalysis analyze({
    required Uint8List wavBytes,
    bool hasTranscript = false,
    bool hasDialect = false,
    bool hasDistrict = false,
    String consentType = 'research_only',
  }) {
    final explanations = <QualityExplanationItem>[];
    final now = DateTime.now();

    // ── FORMAT CHECKS ─────────────────────────────────────────────────────────
    bool formatValid = false;
    int? sampleRateHz;
    int? channels;
    int? bitDepth;
    int? durationMs;
    final fileSizeBytes = wavBytes.length;

    try {
      final info = parseWavHeader(wavBytes);
      formatValid = true;
      sampleRateHz = info.sampleRate;
      channels = info.channels;
      bitDepth = 16; // parseWavHeader only succeeds for 16-bit
      durationMs = info.durationMs;

      explanations.add(QualityExplanationItem(
        check: 'format_valid',
        passed: true,
        message: '✓ Valid WAV (PCM, 16-bit)',
      ));
      explanations.add(QualityExplanationItem(
        check: 'sample_rate',
        passed: sampleRateHz == 16000,
        message: sampleRateHz == 16000
            ? '✓ 16 kHz sample rate'
            : '✗ Sample rate is $sampleRateHz Hz (expected 16000)',
      ));
      explanations.add(QualityExplanationItem(
        check: 'channels',
        passed: channels == 1,
        message:
            channels == 1 ? '✓ Mono audio' : '✗ $channels channels (expected mono)',
      ));
    } on Exception catch (e) {
      explanations.add(QualityExplanationItem(
        check: 'format_valid',
        passed: false,
        message: '✗ Invalid WAV: ${e.toString()}',
      ));
    }

    // ── DURATION CHECK ─────────────────────────────────────────────────────────
    if (durationMs != null) {
      const minMs = 1000;
      const maxMs = 30000;
      final durationOk = durationMs >= minMs && durationMs <= maxMs;
      explanations.add(QualityExplanationItem(
        check: 'duration',
        passed: durationOk,
        message: durationOk
            ? '✓ Duration: ${(durationMs / 1000).toStringAsFixed(1)}s'
            : '⚠ Duration: ${(durationMs / 1000).toStringAsFixed(1)}s (expected 1–30s)',
      ));
    }

    // ── FILE SIZE CHECK ────────────────────────────────────────────────────────
    const maxBytes = 5 * 1024 * 1024; // 5MB
    explanations.add(QualityExplanationItem(
      check: 'file_size',
      passed: fileSizeBytes <= maxBytes,
      message: fileSizeBytes <= maxBytes
          ? '✓ File size: ${(fileSizeBytes / 1024).toStringAsFixed(0)} KB'
          : '✗ File too large: ${(fileSizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
    ));

    // ── VOLUME ANALYSIS (real, from PCM samples) ───────────────────────────────
    double? peakAmplitudeDb;
    double? rmsDb;
    bool? clippingDetected;

    if (formatValid && durationMs != null && wavBytes.length >= 44) {
      final pcmAnalysis = _analyzePcmVolume(wavBytes);
      peakAmplitudeDb = pcmAnalysis.peakDb;
      rmsDb = pcmAnalysis.rmsDb;
      clippingDetected = pcmAnalysis.clippingDetected;

      final volOk = rmsDb != null && rmsDb > -40.0;
      explanations.add(QualityExplanationItem(
        check: 'volume',
        passed: volOk,
        message: volOk
            ? '✓ Audio volume adequate (RMS: ${rmsDb.toStringAsFixed(1)} dBFS)'
            : '⚠ Low audio volume (RMS: ${rmsDb?.toStringAsFixed(1) ?? "?"} dBFS)',
      ));

      if (clippingDetected == true) {
        explanations.add(QualityExplanationItem(
          check: 'clipping',
          passed: false,
          message: '⚠ Possible audio clipping detected (peak at or near 0 dBFS)',
        ));
      } else {
        explanations.add(QualityExplanationItem(
          check: 'clipping',
          passed: true,
          message: '✓ No clipping detected',
        ));
      }
    }

    // ── SILENCE RATIO (heuristic from actual samples) ─────────────────────────
    double? silenceRatio;
    bool? speechPresence;
    if (formatValid && wavBytes.length >= 44) {
      silenceRatio = _computeSilenceRatio(wavBytes);
      speechPresence = silenceRatio < 0.8; // >20% non-silent frames

      explanations.add(QualityExplanationItem(
        check: 'speech_presence',
        passed: speechPresence,
        message: speechPresence
            ? '✓ Speech content detected (silence ratio: ${(silenceRatio * 100).toStringAsFixed(0)}%)'
            : '⚠ Very high silence ratio (${(silenceRatio * 100).toStringAsFixed(0)}%) — may be silent or corrupted',
      ));
    }

    // ── HASH (for duplicate detection) ────────────────────────────────────────
    final audioSha256 = sha256.convert(wavBytes).toString();

    // ── METADATA QUALITY ──────────────────────────────────────────────────────
    if (hasDialect) {
      explanations.add(QualityExplanationItem(
        check: 'dialect_provided',
        passed: true,
        message: '✓ Dialect specified',
      ));
    } else {
      explanations.add(QualityExplanationItem(
        check: 'dialect_provided',
        passed: false,
        message: '⚠ No dialect specified',
      ));
    }

    if (hasDistrict) {
      explanations.add(QualityExplanationItem(
        check: 'location_provided',
        passed: true,
        message: '✓ Recording location specified',
      ));
    }

    if (hasTranscript) {
      explanations.add(QualityExplanationItem(
        check: 'transcript_provided',
        passed: true,
        message: '✓ Transcript provided',
      ));
    }

    // ── ADVANCED ANALYSIS (unavailable without ML) ────────────────────────────
    // Explicitly mark as unavailable — do NOT fabricate SNR or noise estimates.
    const advancedAnalysisStatus = 'unavailable';

    // ── SCORE COMPUTATION ─────────────────────────────────────────────────────
    final audioScore = _computeAudioScore(
      formatValid: formatValid,
      sampleRateHz: sampleRateHz,
      channels: channels,
      durationMs: durationMs,
      fileSizeOk: fileSizeBytes <= maxBytes,
      speechPresence: speechPresence,
      silenceRatio: silenceRatio,
      clippingDetected: clippingDetected,
      rmsDb: rmsDb,
    );

    final metadataScore = _computeMetadataScore(
      hasDialect: hasDialect,
      hasDistrict: hasDistrict,
      hasTranscript: hasTranscript,
    );

    final consentScore = _computeConsentScore(consentType: consentType);

    final overallScore = (audioScore * 0.6 +
            metadataScore * 0.25 +
            consentScore * 0.15)
        .round()
        .clamp(0, 100);

    return QualityAnalysis(
      formatValid: formatValid,
      sampleRateHz: sampleRateHz,
      channels: channels,
      bitDepth: bitDepth,
      durationMs: durationMs,
      fileSizeBytes: fileSizeBytes,
      speechPresence: speechPresence,
      silenceRatio: silenceRatio,
      clippingDetected: clippingDetected,
      peakAmplitudeDb: peakAmplitudeDb,
      rmsDb: rmsDb,
      audioSha256: audioSha256,
      audioQualityScore: audioScore,
      metadataQualityScore: metadataScore,
      consentQualityScore: consentScore,
      overallQualityScore: overallScore,
      advancedAnalysisStatus: advancedAnalysisStatus,
      qualityExplanation: explanations,
      computedAt: now,
    );
  }

  // ── PRIVATE HELPERS ──────────────────────────────────────────────────────────

  /// Analyze PCM volume from WAV bytes.
  /// Reads actual sample values from the data chunk.
  static _PcmVolumeResult _analyzePcmVolume(Uint8List wavBytes) {
    // Find data chunk offset (scan past header)
    final bd = ByteData.sublistView(wavBytes);
    int offset = 12;
    int dataOffset = -1;
    int dataSize = 0;

    while (offset < wavBytes.length - 8) {
      final chunkId = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize;
    }

    if (dataOffset < 0 || dataSize < 2) {
      return _PcmVolumeResult(peakDb: null, rmsDb: null, clippingDetected: null);
    }

    final end = (dataOffset + dataSize).clamp(0, wavBytes.length);
    final sampleCount = (end - dataOffset) ~/ 2; // 16-bit = 2 bytes per sample
    if (sampleCount == 0) {
      return _PcmVolumeResult(peakDb: null, rmsDb: null, clippingDetected: null);
    }

    double sumSquares = 0.0;
    double peak = 0.0;
    bool clipping = false;
    const clippingThreshold = 32700; // ~0.99 of 32767

    for (int i = 0; i < sampleCount; i++) {
      final samplePos = dataOffset + i * 2;
      if (samplePos + 2 > wavBytes.length) break;
      final sample = bd.getInt16(samplePos, Endian.little).abs().toDouble();
      sumSquares += sample * sample;
      if (sample > peak) peak = sample;
      if (sample >= clippingThreshold) clipping = true;
    }

    const maxSample = 32768.0;
    final rms = sampleCount > 0 ? (sumSquares / sampleCount) : 0.0;
    final rmsLinear = rms > 0 ? (rms.isFinite ? rms : 0.0) : 0.0;
    final rmsSqrt = rmsLinear > 0 ? _sqrt(rmsLinear) : 0.0;
    final rmsDb = rmsSqrt > 0 ? 20 * _log10(rmsSqrt / maxSample) : -96.0;
    final peakDb = peak > 0 ? 20 * _log10(peak / maxSample) : -96.0;

    return _PcmVolumeResult(
      peakDb: peakDb,
      rmsDb: rmsDb,
      clippingDetected: clipping,
    );
  }

  /// Compute the fraction of "silent" frames in the audio.
  /// A frame is silent if all samples are below a threshold.
  static double _computeSilenceRatio(Uint8List wavBytes) {
    final bd = ByteData.sublistView(wavBytes);
    int offset = 12;
    int dataOffset = -1;
    int dataSize = 0;

    while (offset < wavBytes.length - 8) {
      final chunkId = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize;
    }

    if (dataOffset < 0) return 1.0;

    const frameSize = 160 * 2; // 10ms at 16kHz, 16-bit
    const silenceThreshold = 500; // ~1.5% of max amplitude
    int silentFrames = 0;
    int totalFrames = 0;
    final end = (dataOffset + dataSize).clamp(0, wavBytes.length);

    int pos = dataOffset;
    while (pos + frameSize <= end) {
      bool isSilent = true;
      for (int i = 0; i < frameSize; i += 2) {
        final sample = bd.getInt16(pos + i, Endian.little).abs();
        if (sample > silenceThreshold) {
          isSilent = false;
          break;
        }
      }
      if (isSilent) silentFrames++;
      totalFrames++;
      pos += frameSize;
    }

    if (totalFrames == 0) return 1.0;
    return silentFrames / totalFrames;
  }

  static int _computeAudioScore({
    required bool formatValid,
    required int? sampleRateHz,
    required int? channels,
    required int? durationMs,
    required bool fileSizeOk,
    required bool? speechPresence,
    required double? silenceRatio,
    required bool? clippingDetected,
    required double? rmsDb,
  }) {
    if (!formatValid) return 0;

    int score = 100;

    if (sampleRateHz != 16000) score -= 20;
    if (channels != 1) score -= 10;
    if (!fileSizeOk) score -= 15;

    if (durationMs != null) {
      if (durationMs < 1000) {
        score -= 30; // too short
      } else if (durationMs < 2000) {
        score -= 10; // quite short
      }
    }

    if (speechPresence == false) score -= 30;

    if (silenceRatio != null && silenceRatio > 0.7) {
      score -= 15;
    } else if (silenceRatio != null && silenceRatio > 0.5) {
      score -= 5;
    }

    if (clippingDetected == true) score -= 10;

    if (rmsDb != null) {
      if (rmsDb < -50) {
        score -= 15; // very quiet
      } else if (rmsDb < -40) {
        score -= 5; // somewhat quiet
      }
    }

    return score.clamp(0, 100);
  }

  static int _computeMetadataScore({
    required bool hasDialect,
    required bool hasDistrict,
    required bool hasTranscript,
  }) {
    int score = 60; // baseline for having any metadata
    if (hasDialect) score += 20;
    if (hasDistrict) score += 15;
    if (hasTranscript) score += 5;
    return score.clamp(0, 100);
  }

  static int _computeConsentScore({required String consentType}) {
    return switch (consentType) {
      'open' => 100,
      'commercial_ai' => 85,
      'research_only' => 70,
      _ => 50,
    };
  }

  // Math helpers (avoid dart:math import for simpler dependency)
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double r = x;
    for (int i = 0; i < 40; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }

  static double _log10(double x) {
    if (x <= 0) return -96;
    // ln(x) / ln(10)
    final ln10 = 2.302585092994046;
    return _ln(x) / ln10;
  }

  static double _ln(double x) {
    if (x <= 0) return -96;
    // Taylor series around 1 — use reduction first
    if (x < 0.5 || x > 2.0) {
      // Use: ln(x) = ln(x * 2^n / 2^n) iterative reduction
      int n = 0;
      double r = x;
      while (r > 2.0) { r /= 2; n++; }
      while (r < 0.5) { r *= 2; n--; }
      return _lnNear1(r) + n * 0.6931471805599453;
    }
    return _lnNear1(x);
  }

  static double _lnNear1(double x) {
    // ln(x) ≈ 2 * arctanh((x-1)/(x+1)) for x near 1
    final y = (x - 1) / (x + 1);
    double sum = 0;
    double term = y;
    for (int i = 0; i < 30; i++) {
      sum += term / (2 * i + 1);
      term *= y * y;
    }
    return 2 * sum;
  }
}


/// Result of quality analysis.
class QualityAnalysis {
  final bool? formatValid;
  final int? sampleRateHz;
  final int? channels;
  final int? bitDepth;
  final int? durationMs;
  final int? fileSizeBytes;
  final bool? speechPresence;
  final double? silenceRatio;
  final bool? clippingDetected;
  final double? peakAmplitudeDb;
  final double? rmsDb;
  final String? audioSha256;
  final int? audioQualityScore;
  final int? metadataQualityScore;
  final int? consentQualityScore;
  final int? overallQualityScore;
  final String advancedAnalysisStatus;
  final List<QualityExplanationItem> qualityExplanation;
  final DateTime computedAt;

  const QualityAnalysis({
    this.formatValid,
    this.sampleRateHz,
    this.channels,
    this.bitDepth,
    this.durationMs,
    this.fileSizeBytes,
    this.speechPresence,
    this.silenceRatio,
    this.clippingDetected,
    this.peakAmplitudeDb,
    this.rmsDb,
    this.audioSha256,
    this.audioQualityScore,
    this.metadataQualityScore,
    this.consentQualityScore,
    this.overallQualityScore,
    this.advancedAnalysisStatus = 'unavailable',
    required this.qualityExplanation,
    required this.computedAt,
  });

  /// Build a human-readable quality report string.
  String get humanReadableReport {
    final buf = StringBuffer();
    buf.writeln('Quality Report');
    buf.writeln('══════════════');
    if (overallQualityScore != null) {
      buf.writeln('Overall Score: $overallQualityScore / 100');
      buf.writeln();
    }
    for (final item in qualityExplanation) {
      buf.writeln(item.message);
    }
    if (advancedAnalysisStatus == 'unavailable') {
      buf.writeln();
      buf.writeln('ℹ Advanced analysis (SNR, noise profiling) requires ML — unavailable');
    }
    return buf.toString();
  }

  Map<String, dynamic> toQualityChecksJson(String dataAssetId) => {
        'data_asset_id': dataAssetId,
        'format_valid': formatValid,
        'sample_rate_hz': sampleRateHz,
        'channels': channels,
        'bit_depth': bitDepth,
        'duration_ms': durationMs,
        'file_size_bytes': fileSizeBytes,
        'speech_presence': speechPresence,
        'silence_ratio': silenceRatio,
        'clipping_detected': clippingDetected,
        'peak_amplitude_db': peakAmplitudeDb,
        'rms_db': rmsDb,
        'audio_sha256': audioSha256,
        'audio_quality_score': audioQualityScore,
        'metadata_quality_score': metadataQualityScore,
        'consent_quality_score': consentQualityScore,
        'overall_quality_score': overallQualityScore,
        'advanced_analysis_status': advancedAnalysisStatus,
        'quality_explanation':
            qualityExplanation.map((e) => e.toJson()).toList(),
        'computed_at': computedAt.toIso8601String(),
      };
}

class _PcmVolumeResult {
  final double? peakDb;
  final double? rmsDb;
  final bool? clippingDetected;
  const _PcmVolumeResult({
    required this.peakDb,
    required this.rmsDb,
    required this.clippingDetected,
  });
}
