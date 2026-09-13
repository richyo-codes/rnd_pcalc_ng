import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcalc_expression_engine/pcalc_expression_engine.dart';

void main() {
  for (final language in [
    ClangExpressionLanguage.cpp17,
    ClangExpressionLanguage.cpp20,
    ClangExpressionLanguage.cpp23,
  ]) {
    test(
      'recursive multiline factorial evaluates in ${language.name}',
      () async {
        // The screenshot reads this same fixture, so the documented example
        // and the evaluated regression case cannot drift apart.
        final expression = await File('test/fixtures/recursive_factorial.cpp')
            .readAsString();
        final session = ExpressionSession(
          preferredBackend: BackendKind.clangConstexpr,
          clangLanguage: language,
        );
        await session.initialize();
        final result = session.evaluate(expression);
        expect(result.backendKind, BackendKind.clangConstexpr);
        expect(result.isError, isFalse, reason: result.errorMessage);
        expect(result.integerValue, 3628800);
        expect(result.bitWidth, 64);
        expect(result.isSigned, isFalse);
      },
      skip: kIsWeb || !canUseClangConstexpr,
    );
  }
}
