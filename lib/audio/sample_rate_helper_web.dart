import 'dart:js_interop';

@JS('window.AudioContext')
extension type AudioContext._(JSObject _) implements JSObject {
  external factory AudioContext();
  external num get sampleRate;
}

int getWebHardwareSampleRate() {
  try {
    final context = AudioContext();
    return context.sampleRate.toInt();
  } catch (e) {
    return 0;
  }
}
