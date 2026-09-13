import 'package:flutter_test/flutter_test.dart';
import 'package:pcalc_express/format_helper.dart';

void main() {
  group('formatHexResult', () {
    test('uses meaningful byte-aligned width for positive values', () {
      expect(formatHexResult(1, bitWidth: 64), '01');
      expect(
        formatHexResult(3628800, bitWidth: 64, isSigned: false),
        '00 37 5F 00',
      );
    });

    test('preserves signed negative two\'s-complement width', () {
      expect(formatHexResult(-1, bitWidth: 32), 'FF FF FF FF');
    });
  });

  group('formatBinaryResult', () {
    test('uses a byte for small positive values', () {
      expect(formatBinaryResult(1, bitWidth: 64), '00000001');
      expect(formatBinaryResult(255, bitWidth: 64), '11111111');
      expect(formatBinaryResult(1, bitWidth: 1), '00000001');
    });

    test('keeps word and dword boundaries without 64-bit zero padding', () {
      expect(formatBinaryResult(256, bitWidth: 64), '00000001 00000000');
      expect(
        formatBinaryResult(3628800, bitWidth: 64, isSigned: false),
        '00000000 00110111 01011111 00000000',
      );
    });

    test('uses 64 bits only when a positive value needs them', () {
      expect(
        formatBinaryResult(1 << 40, bitWidth: 64, isSigned: false),
        '00000000 00000000 00000001 00000000 00000000 00000000 00000000 00000000',
      );
    });

    test('preserves signed negative two\'s-complement width', () {
      expect(
        formatBinaryResult(-1, bitWidth: 32),
        '11111111 11111111 11111111 11111111',
      );
      expect(formatBinaryResult(-1, bitWidth: 8), '11111111');
    });
  });
}
