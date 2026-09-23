import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/audio/resampler.dart';

void main() {
  test('Resampler - correctly resamples 48000Hz to 16000Hz', () {
    // 1 second at 48000Hz (48000 samples * 2 = 96000 bytes)
    final inputPcm = Uint8List(96000);
    final intData = ByteData.sublistView(inputPcm);
    
    // Fill with a simple pattern
    for (int i = 0; i < 48000; i++) {
      intData.setInt16(i * 2, i % 1000, Endian.little);
    }
    
    final outputPcm = resamplePcm16(inputPcm, 48000, 16000);
    
    // Expect 1/3 of the length (16000 samples * 2 = 32000 bytes)
    expect(outputPcm.length, 32000);
    
    // Values should be interpolated correctly
    final outIntData = ByteData.sublistView(outputPcm);
    final val0 = outIntData.getInt16(0, Endian.little);
    final val1 = outIntData.getInt16(2, Endian.little); // Should map to index 3 in original
    
    expect(val0, 0);
    expect(val1, 3);
  });
}
