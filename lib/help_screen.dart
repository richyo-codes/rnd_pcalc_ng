import 'package:flutter/material.dart';
import 'package:pcalc_express/app_brand.dart';
import 'package:pcalc_express/window_drag_controller.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.themeColor});
  final MaterialColor themeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FramelessWindowResizeFrame(
      child: Scaffold(
        appBar: WindowChromeHeader(
          title: const AppTitleLabel(),
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Calculator'),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 16),
                  Text('Help', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Write an expression. Inspect its value in different number bases.',
                  ),
                  const _HelpSection(
                    'Edit and calculate',
                    'Press Enter or Calculate to evaluate. Ctrl+E focuses the expression. The arrow buttons move the cursor; keypad buttons insert at the cursor or replace selected text. DEL removes text and AC clears the expression. Bracket highlighting helps identify matching pairs and unbalanced brackets.',
                  ),
                  const _HelpSection(
                    'Multiline expressions',
                    'Use the expand button inside the expression field for multiple lines. Drag the grip below the expanded field to adjust its height. Enter inserts a newline in expanded mode; Ctrl+Enter or Command+Enter calculates. The newline button works with the system keyboard off. Collapsing preserves the expression, cursor position, and chosen height.',
                  ),
                  const _HelpSection(
                    'Try these with Clang constexpr',
                    'The selected C/C++ language controls the rules. Integer division truncates; use a decimal point for floating-point division. The ^ operator is bitwise XOR, not exponentiation.',
                  ),
                  const SelectableText(
                    '1 << 10 → 1024\n0xff & 0x0f → 15\n7 / 2 → 3\n7.0 / 2 → 3.5\n(unsigned char)255 → 255',
                    style: TextStyle(fontFamily: 'monospace', height: 1.8),
                  ),
                  const _HelpSection(
                    'Read the results',
                    'Decimal, hexadecimal, binary, and floating-point views show the result in different formats. Use the copy button beside a value to copy it. Typed backends supply integer width and signedness, which affect the bit representation. In compact layouts, select a result tab or use Show all result units to expand.',
                  ),
                  const _HelpSection(
                    'History and layout',
                    'Open the application menu for History and reuse a previous expression. The same menu contains Settings, theme switching, and keypad visibility. The keypad adapts to the available space, with general arithmetic and programmer operators.',
                  ),
                  const _HelpSection(
                    'Choose your expression language',
                    'Settings → Advanced contains the backend and Clang language options. Clang constexpr evaluates constant C/C++ expressions; it is not a general program runner. Do not assume standard-library headers or functions are available. TinyExpr++ has its own formula syntax. ROOT formula and Cling have different capabilities and need a compatible installation. Availability depends on the platform, and Auto may select a fallback.',
                  ),
                  const _HelpSection(
                    'If an expression fails',
                    'Check brackets, the selected backend, and the language standard first. Syntax that works in one backend may not work in another. For subprocess troubleshooting, enable debug backend command logging in Settings to print commands and results to the console.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection(this.title, this.text);
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(height: 1.5)),
      ],
    ),
  );
}
