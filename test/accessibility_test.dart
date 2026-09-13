import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcalc_express/calculator.dart';

void main() {
  testWidgets('calculator exposes meaningful control and result semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CalculatorScreen(
          showCalcButtonsDesktop: true,
          themeColor: Colors.red,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Enter Expression'), findsOneWidget);
    expect(find.bySemanticsLabel('Decimal result'), findsOneWidget);
    expect(find.bySemanticsLabel('Hexadecimal result'), findsOneWidget);
    expect(find.bySemanticsLabel('Binary result'), findsOneWidget);
    expect(find.bySemanticsLabel('Floating Point result'), findsOneWidget);
    expect(find.bySemanticsLabel('Copy Decimal result'), findsOneWidget);
    expect(find.bySemanticsLabel('Calculate'), findsWidgets);
    expect(find.bySemanticsLabel('Divide'), findsOneWidget);
    expect(find.bySemanticsLabel('Multiply'), findsOneWidget);
    expect(find.bySemanticsLabel('Decimal point'), findsOneWidget);
    expect(find.bySemanticsLabel('Application menu'), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    semantics.dispose();
  });
}
