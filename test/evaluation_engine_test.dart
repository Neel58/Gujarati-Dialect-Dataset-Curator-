import 'package:flutter_test/flutter_test.dart';
import 'package:gujarati_dialect_curator/services/evaluation_engine.dart';

void main() {
  group('EvaluationEngine - Mathematical Alignment & WER/CER', () {
    test('Identical reference and hypothesis yield WER=0 and CER=0', () {
      const ref = 'નમસ્તે ગુજરાત કેમ છો';
      const hyp = 'નમસ્તે ગુજરાત કેમ છો';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(4));
      expect(res.hypothesisWordCount, equals(4));
      expect(res.substitutions, equals(0));
      expect(res.deletions, equals(0));
      expect(res.insertions, equals(0));
      expect(res.wer, equals(0.0));
      expect(res.cer, equals(0.0));
    });

    test('Single substitution mathematically verified', () {
      // ref: 3 words, hyp: 3 words, 1 word replaced
      const ref = 'હું ઘેર જાઉં';
      const hyp = 'હું ગામ જાઉં';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(3));
      expect(res.substitutions, equals(1));
      expect(res.deletions, equals(0));
      expect(res.insertions, equals(0));
      // WER = (1 + 0 + 0) / 3 = 0.3333...
      expect(res.wer, closeTo(1.0 / 3.0, 0.001));
    });

    test('Single deletion mathematically verified', () {
      // ref: 4 words, hyp: 3 words (missing 1 word)
      const ref = 'હું આજે ઘેર જાઉં';
      const hyp = 'હું ઘેર જાઉં';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(4));
      expect(res.substitutions, equals(0));
      expect(res.deletions, equals(1));
      expect(res.insertions, equals(0));
      // WER = 1 / 4 = 0.25
      expect(res.wer, equals(0.25));
    });

    test('Single insertion mathematically verified', () {
      // ref: 3 words, hyp: 4 words (extra word inserted)
      const ref = 'હું ઘેર જાઉં';
      const hyp = 'હું આજે ઘેર જાઉં';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(3));
      expect(res.substitutions, equals(0));
      expect(res.deletions, equals(0));
      expect(res.insertions, equals(1));
      // WER = 1 / 3 = 0.333...
      expect(res.wer, closeTo(1.0 / 3.0, 0.001));
    });

    test('Combined substitution + deletion + insertion', () {
      // ref: "a b c d" (4 words)
      // hyp: "a x d e" (4 words: 'b' substituted with 'x', 'c' deleted, 'e' inserted)
      const ref = 'a b c d';
      const hyp = 'a x d e';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(4));
      // Distance is:
      // a == a (0)
      // b -> x (1 sub)
      // c -> deleted (1 del)
      // d == d (0)
      // e inserted (1 ins)
      // Total errors = 3 -> WER = 3/4 = 0.75
      expect(res.substitutions + res.deletions + res.insertions, equals(3));
      expect(res.wer, equals(0.75));
    });

    test('Empty reference and non-empty hypothesis', () {
      const ref = '';
      const hyp = 'કંઈક કહ્યું';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(0));
      expect(res.wer, equals(1.0));
    });

    test('Empty hypothesis and non-empty reference', () {
      const ref = 'નમસ્તે ગુજરાત';
      const hyp = '';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(2));
      expect(res.deletions, equals(2));
      expect(res.wer, equals(1.0));
    });

    test('Both reference and hypothesis empty', () {
      const ref = '';
      const hyp = '';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(0));
      expect(res.hypothesisWordCount, equals(0));
      expect(res.wer, equals(0.0));
      expect(res.cer, equals(0.0));
    });

    test('Whitespace and token normalization: ignores variable whitespace and newlines', () {
      const ref = '  નમસ્તે   ગુજરાત \n  કેમ   છો  ';
      const hyp = 'નમસ્તે ગુજરાત કેમ છો';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceWordCount, equals(4));
      expect(res.hypothesisWordCount, equals(4));
      expect(res.wer, equals(0.0));
      expect(res.cer, equals(0.0));
    });

    test('Unicode Gujarati Character Error Rate (CER): mathematically verified', () {
      // ref: "ગુજરાત" -> 6 characters: ગ, ુ, જ, ર, ા, ત
      // hyp: "ગુજરાતી" -> 7 characters: ગ, ુ, જ, ર, ા, ત, ી (1 insertion)
      const ref = 'ગુજરાત';
      const hyp = 'ગુજરાતી';

      final res = EvaluationEngine.align(ref, hyp);

      expect(res.referenceCharCount, equals(6));
      expect(res.hypothesisCharCount, equals(7));
      expect(res.charInsertions, equals(1));
      expect(res.charDeletions, equals(0));
      expect(res.charSubstitutions, equals(0));
      expect(res.cer, closeTo(1.0 / 6.0, 0.001));
    });
  });

  group('EvaluationEngine - Batch & Category Breakdown', () {
    test('Computes overall WER, category WER and generates recommendations', () {
      final items = [
        const BenchmarkEvaluationInput(
          id: 'item-1',
          reference: 'નમસ્તે ગુજરાત કેમ છો',
          hypothesis: 'નમસ્તે ગુજરાત કેમ છો', // 0 errors
          category: 'standard',
        ),
        const BenchmarkEvaluationInput(
          id: 'item-2',
          reference: 'આજે ખૂબ વરસાદ છે',
          hypothesis: 'આજે ખૂબ વરસાદ છે', // 0 errors
          category: 'standard',
        ),
        const BenchmarkEvaluationInput(
          id: 'item-3',
          reference: 'અમે કાલે અમદાવાદ જવાના છીએ',
          hypothesis: 'અમે કાલે સુરત જવાના છીએ', // 1 sub in 5 words = 0.20
          category: 'kathiyawadi',
          dialectId: 2,
        ),
        const BenchmarkEvaluationInput(
          id: 'item-4',
          reference: 'તમે ક્યાં રહો છો ભાઈ',
          hypothesis: 'તમે ક્યાં રહો બેન', // 1 sub, 1 del in 5 words = 0.40
          category: 'kathiyawadi',
          dialectId: 2,
        ),
      ];

      final summary = EvaluationEngine.evaluateBatch(items);

      expect(summary.totalSamples, equals(4));
      expect(summary.categoryBreakdown.containsKey('standard'), isTrue);
      expect(summary.categoryBreakdown['standard']!.wer, equals(0.0));
      expect(summary.categoryBreakdown.containsKey('kathiyawadi'), isTrue);
      expect(summary.categoryBreakdown['kathiyawadi']!.wer, greaterThan(0.20));

      // Check recommendation generated for high error category
      expect(summary.recommendations.isNotEmpty, isTrue);
      final rec = summary.recommendations.first;
      expect(rec.targetCategory, equals('kathiyawadi'));
      expect(rec.dialectId, equals('2'));
      expect(rec.priority, isNotNull);
    });
  });
}
