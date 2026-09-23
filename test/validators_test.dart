import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/utils/validators.dart';

void main() {
  group('Validators - isGujaratiValid', () {
    test('Valid pure Gujarati', () {
      expect(Validators.isGujaratiValid('નમસ્તે તમે કેમ છો'), isTrue);
    });
    
    test('Mixed text with > 50% Gujarati', () {
      expect(Validators.isGujaratiValid('Hello નમસ્તે તમે કેમ છો'), isTrue);
    });

    test('Mixed text with < 50% Gujarati', () {
      expect(Validators.isGujaratiValid('Hello world નમસ્તે'), isFalse);
    });

    test('Pure English text', () {
      expect(Validators.isGujaratiValid('Hello world'), isFalse);
    });

    test('Only spaces', () {
      expect(Validators.isGujaratiValid('   '), isFalse);
    });

    test('Empty string', () {
      expect(Validators.isGujaratiValid(''), isFalse);
    });

    test('Gujarati with numbers and punctuation', () {
      expect(Validators.isGujaratiValid('મારું નામ 123 છે!'), isTrue); // "મારું નામ છે" is 10 chars, "123!" is 4 chars. 10/14 > 50%
    });
  });
}
