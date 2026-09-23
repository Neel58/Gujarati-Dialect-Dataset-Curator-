import 'dart:typed_data';

Uint8List buildWav({
  required Uint8List pcmBytes,
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final byteRate = (sampleRate * channels * bitsPerSample) ~/ 8;
  final blockAlign = (channels * bitsPerSample) ~/ 8;
  final dataSize = pcmBytes.length;
  final fileSize = 36 + dataSize;

  final builder = BytesBuilder();

  // RIFF chunk
  builder.add('RIFF'.codeUnits);
  builder.add(_uint32Bytes(fileSize));
  builder.add('WAVE'.codeUnits);

  // fmt chunk
  builder.add('fmt '.codeUnits);
  builder.add(_uint32Bytes(16)); // Subchunk1Size
  builder.add(_uint16Bytes(1)); // AudioFormat (PCM = 1)
  builder.add(_uint16Bytes(channels));
  builder.add(_uint32Bytes(sampleRate));
  builder.add(_uint32Bytes(byteRate));
  builder.add(_uint16Bytes(blockAlign));
  builder.add(_uint16Bytes(bitsPerSample));

  // data chunk
  builder.add('data'.codeUnits);
  builder.add(_uint32Bytes(dataSize));
  builder.add(pcmBytes);

  return builder.toBytes();
}

Uint8List _uint32Bytes(int value) {
  final bd = ByteData(4);
  bd.setUint32(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List _uint16Bytes(int value) {
  final bd = ByteData(2);
  bd.setUint16(0, value, Endian.little);
  return bd.buffer.asUint8List();
}
