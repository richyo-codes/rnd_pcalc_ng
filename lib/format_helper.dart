String formatHexResult(
  int intValue, {
  int bitWidth = 32,
  bool isSigned = true,
}) {
  final sanitizedBitWidth = bitWidth.clamp(1, 64);
  final significantBits = intValue == 0 ? 1 : intValue.bitLength;
  final compactWidth = significantBits <= 8
      ? 8
      : significantBits <= 16
      ? 16
      : significantBits <= 32
      ? 32
      : 64;
  final maximumDisplayWidth = sanitizedBitWidth < 8 ? 8 : sanitizedBitWidth;
  final bitWidthToUse = intValue < 0 && isSigned
      ? sanitizedBitWidth
      : compactWidth.clamp(8, maximumDisplayWidth).toInt();
  final hexDigits = (bitWidthToUse / 4).ceil();
  final hex = intValue
      .toUnsigned(bitWidthToUse)
      .toRadixString(16)
      .toUpperCase()
      .padLeft(hexDigits, '0');
  return hex
      .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)} ')
      .trim();
}

String formatBinaryResult(
  int intValue, {
  int bitWidth = 32,
  bool isSigned = true,
}) {
  final sanitizedBitWidth = bitWidth.clamp(1, 64);

  // For positive values, the declared C/C++ type is useful metadata but does
  // not need to consume the display with zeroes. Preserve conventional byte,
  // word, and dword boundaries. Negative signed values retain the full width,
  // since their leading one bits are part of the two's-complement value.
  final significantBits = intValue == 0 ? 1 : intValue.bitLength;
  final compactWidth = significantBits <= 8
      ? 8
      : significantBits <= 16
      ? 16
      : significantBits <= 32
      ? 32
      : 64;
  final maximumDisplayWidth = sanitizedBitWidth < 8 ? 8 : sanitizedBitWidth;
  final bitWidthToUse = intValue < 0 && isSigned
      ? sanitizedBitWidth
      : compactWidth.clamp(8, maximumDisplayWidth).toInt();
  final normalizedValue = intValue.toUnsigned(bitWidthToUse);

  final binary = normalizedValue
      .toRadixString(2)
      .toUpperCase()
      .padLeft(bitWidthToUse, '0');

  return binary
      .replaceAllMapped(RegExp(r'.{8}'), (match) => '${match.group(0)} ')
      .trim();
}

String formatFloatResult(double value) {
  // Format float with 6 decimal places
  return value.toStringAsFixed(6);
}
