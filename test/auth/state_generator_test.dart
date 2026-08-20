import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/src/auth/state_generator.dart';

void main() {
  group('UaePassStateGenerator', () {
    test('generates non-empty, URL-safe strings', () {
      final state = UaePassStateGenerator.generate();
      expect(state, isNotEmpty);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(state), isTrue);
      expect(state.contains('='), isFalse);
    });

    test('never repeats across many calls, unlike a hardcoded default', () {
      final generated = <String>{
        for (var i = 0; i < 200; i++) UaePassStateGenerator.generate(),
      };
      expect(generated, hasLength(200));
    });

    test('honours a custom byte length', () {
      final short = UaePassStateGenerator.generate(byteLength: 8);
      final long = UaePassStateGenerator.generate(byteLength: 64);
      expect(long.length, greaterThan(short.length));
    });
  });
}
