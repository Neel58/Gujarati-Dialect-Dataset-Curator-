import 'dart:typed_data';
import 'quality_engine.dart';

/// Provider availability states.
enum ProviderStatus {
  available,
  unconfigured,
  unavailable,
  error,
}

/// Generic provider response wrapper that explicitly declares availability.
class ProviderResponse<T> {
  final ProviderStatus status;
  final T? data;
  final String? message;

  const ProviderResponse.success(this.data)
      : status = ProviderStatus.available,
        message = null;

  const ProviderResponse.unavailable([this.message = 'Provider is not configured or ML service is unavailable'])
      : status = ProviderStatus.unavailable,
        data = null;

  const ProviderResponse.unconfigured([this.message = 'API credentials or endpoint not provided'])
      : status = ProviderStatus.unconfigured,
        data = null;

  const ProviderResponse.error(this.message)
      : status = ProviderStatus.error,
        data = null;

  bool get isAvailable => status == ProviderStatus.available && data != null;
}

/// Abstract contract for Speech-to-Text (ASR) transcription.
abstract class TranscriptionProvider {
  String get name;
  Future<ProviderResponse<String>> transcribe(Uint8List audioBytes, {String? languageCode});
}

/// Honest default implementation when external ML ASR service is unavailable.
/// NEVER fabricates transcripts.
class UnavailableTranscriptionProvider implements TranscriptionProvider {
  @override
  String get name => 'Unavailable Transcription Provider';

  @override
  Future<ProviderResponse<String>> transcribe(Uint8List audioBytes, {String? languageCode}) async {
    return const ProviderResponse.unavailable(
      'Gujarati ASR model inference service is not configured in this environment.',
    );
  }
}

/// Result of dialect detection with dialect classification and confidence.
class DialectDetectionResult {
  final String dialectName;
  final int dialectId;
  final double confidence;

  const DialectDetectionResult({
    required this.dialectName,
    required this.dialectId,
    required this.confidence,
  });
}

/// Abstract contract for Dialect Identification (DID).
abstract class DialectDetectionProvider {
  String get name;
  Future<ProviderResponse<DialectDetectionResult>> detectDialect(Uint8List audioBytes);
}

/// Honest default implementation when ML dialect classifier is unavailable.
/// NEVER guesses or returns random fake confidences.
class UnavailableDialectDetectionProvider implements DialectDetectionProvider {
  @override
  String get name => 'Unavailable Dialect Provider';

  @override
  Future<ProviderResponse<DialectDetectionResult>> detectDialect(Uint8List audioBytes) async {
    return const ProviderResponse.unavailable(
      'Gujarati dialect acoustic classifier model is not configured. Manual labeling is required.',
    );
  }
}

/// Abstract contract for audio quality analysis.
abstract class QualityAnalysisProvider {
  String get name;
  QualityAnalysis analyzeAudio({
    required Uint8List wavBytes,
    bool hasTranscript = false,
    bool hasDialect = false,
    bool hasDistrict = false,
    String consentType = 'research_only',
  });
}

/// Production quality provider using real deterministic PCM heuristics (QualityEngine).
/// Advanced ML features (SNR, background separation) are kept explicitly as unavailable.
class LocalHeuristicQualityProvider implements QualityAnalysisProvider {
  @override
  String get name => 'Deterministic Audio Quality Engine';

  @override
  QualityAnalysis analyzeAudio({
    required Uint8List wavBytes,
    bool hasTranscript = false,
    bool hasDialect = false,
    bool hasDistrict = false,
    String consentType = 'research_only',
  }) {
    return QualityEngine.analyze(
      wavBytes: wavBytes,
      hasTranscript: hasTranscript,
      hasDialect: hasDialect,
      hasDistrict: hasDistrict,
      consentType: consentType,
    );
  }
}
