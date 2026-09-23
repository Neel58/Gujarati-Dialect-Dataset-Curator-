import 'dart:typed_data';

Uint8List resamplePcm16(Uint8List input, int inputRate, int outputRate) {
  if (inputRate == outputRate) return input;
  
  final numSamples = input.length ~/ 2;
  final numOutputSamples = (numSamples * outputRate) ~/ inputRate;
  
  final inputData = ByteData.sublistView(input);
  final outputBytes = Uint8List(numOutputSamples * 2);
  final outputData = ByteData.sublistView(outputBytes);
  
  final ratio = inputRate / outputRate;
  
  for (int i = 0; i < numOutputSamples; i++) {
    final mappedIndex = i * ratio;
    final leftIndex = mappedIndex.floor();
    final rightIndex = mappedIndex.ceil();
    final fraction = mappedIndex - leftIndex;
    
    int leftSample = 0;
    if (leftIndex >= 0 && leftIndex < numSamples) {
      leftSample = inputData.getInt16(leftIndex * 2, Endian.little);
    }
    
    int rightSample = leftSample;
    if (rightIndex >= 0 && rightIndex < numSamples) {
      rightSample = inputData.getInt16(rightIndex * 2, Endian.little);
    }
    
    final interpolated = (leftSample + (rightSample - leftSample) * fraction).round();
    
    // Clamp to 16-bit range
    final clamped = interpolated.clamp(-32768, 32767);
    outputData.setInt16(i * 2, clamped, Endian.little);
  }
  
  return outputBytes;
}
