import 'dart:typed_data';

class WavInfo {
  final int durationMs;
  final int sampleRate;
  final int channels;

  WavInfo({required this.durationMs, required this.sampleRate, required this.channels});
}

WavInfo parseWavHeader(Uint8List bytes) {
  if (bytes.length < 44) throw Exception('File too short to be a valid WAV');
  
  final stringStart = String.fromCharCodes(bytes.sublist(0, 4));
  if (stringStart != 'RIFF') throw Exception('Not a RIFF file');
  
  final format = String.fromCharCodes(bytes.sublist(8, 12));
  if (format != 'WAVE') throw Exception('Not a WAVE file');

  final byteData = ByteData.sublistView(bytes);
  
  final audioFormat = byteData.getUint16(20, Endian.little);
  if (audioFormat != 1) throw Exception('Not uncompressed PCM (format $audioFormat)');

  final numChannels = byteData.getUint16(22, Endian.little);
  if (numChannels != 1) throw Exception('Must be mono (1 channel), got $numChannels');

  final sampleRate = byteData.getUint32(24, Endian.little);
  if (sampleRate != 16000) throw Exception('Must be 16000 Hz, got $sampleRate');

  final bitsPerSample = byteData.getUint16(34, Endian.little);
  if (bitsPerSample != 16) throw Exception('Must be 16-bit, got $bitsPerSample');

  // Find data chunk to get length
  int offset = 12;
  while (offset < bytes.length - 8) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = byteData.getUint32(offset + 4, Endian.little);
    if (chunkId == 'data') {
      final dataSize = chunkSize;
      final durationMs = (dataSize / (sampleRate * numChannels * (bitsPerSample / 8)) * 1000).round();
      return WavInfo(durationMs: durationMs, sampleRate: sampleRate, channels: numChannels);
    }
    offset += 8 + chunkSize;
  }
  
  throw Exception('No data chunk found');
}
