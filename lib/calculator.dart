import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pcalc_express/app_brand.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pcalc_express/platform_capabilities.dart';
import 'package:pcalc_express/theme_preferences.dart';
import 'package:pcalc_express/input_preferences.dart';
import 'package:pcalc_express/window_drag_controller.dart';
import 'package:pcalc_express/settings_page.dart';

import 'package:pcalc_expression_engine/pcalc_expression_engine.dart';

import 'feature_flags.dart';

import 'package:pcalc_express/help_screen.dart';
import 'package:pcalc_express/format_helper.dart';

final Uri _sourceCodeUri = Uri.parse(
  'https://github.com/richyo-codes/pcalc-express',
);

class AppScrollBehavior extends MaterialScrollBehavior {
  // Enable drag with mouse/trackpad on desktop (touch already works on mobile)
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}

class CalcPageIndicator extends StatelessWidget {
  final int pageCount;
  final int currentPage;
  final ValueChanged<int>? onDotTapped;
  final Color activeColor;
  final Color inactiveColor;

  const CalcPageIndicator({
    Key? key,
    required this.pageCount,
    required this.currentPage,
    this.onDotTapped,
    this.activeColor = Colors.red,
    this.inactiveColor = Colors.grey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        pageCount,
        (index) => GestureDetector(
          onTap: onDotTapped != null ? () => onDotTapped!(index) : null,
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: currentPage == index ? activeColor : inactiveColor,
            ),
          ),
        ),
      ),
    );
  }
}

class CalcButtonConfig {
  final String displayText;
  final String insertText;
  final String? tooltip;
  final void Function(BuildContext context)? onPressed;

  const CalcButtonConfig({
    required this.displayText,
    String? insertText,
    this.tooltip,
    this.onPressed,
  }) : insertText = insertText ?? displayText;
}

enum _CalcButtonRole {
  number,
  operator,
  programmer,
  utility,
  destructive,
  equals,
}

class _FocusExpressionIntent extends Intent {
  const _FocusExpressionIntent();
}

class _CalculateExpressionIntent extends Intent {
  const _CalculateExpressionIntent();
}

enum _ResultDisplayMode { adaptive, expanded, compact }

final class _BracketAnalysis {
  const _BracketAnalysis({
    required this.pairs,
    required this.unmatchedOffsets,
    required this.activePair,
  });

  final Map<int, int> pairs;
  final Set<int> unmatchedOffsets;
  final Set<int> activePair;

  bool get hasError => unmatchedOffsets.isNotEmpty;
  bool get hasActivePair => activePair.isNotEmpty;

  String get statusMessage {
    if (unmatchedOffsets.isEmpty) {
      return hasActivePair ? 'Matching brackets' : 'Brackets balanced';
    }
    return unmatchedOffsets.length == 1
        ? 'Unmatched bracket'
        : '${unmatchedOffsets.length} unmatched brackets';
  }

  factory _BracketAnalysis.forText(String text, int cursorOffset) {
    final pairs = <int, int>{};
    final unmatched = <int>{};
    final openings = <({int offset, String character})>[];
    const closingFor = {')': '(', ']': '[', '}': '{'};

    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      if (character == '(' || character == '[' || character == '{') {
        openings.add((offset: index, character: character));
        continue;
      }
      final opening = closingFor[character];
      if (opening == null) continue;
      if (openings.isEmpty || openings.last.character != opening) {
        unmatched.add(index);
        continue;
      }
      final matchedOpening = openings.removeLast();
      pairs[matchedOpening.offset] = index;
      pairs[index] = matchedOpening.offset;
    }
    unmatched.addAll(openings.map((bracket) => bracket.offset));

    final activePair = <int>{};
    final candidates = <int>{
      if (cursorOffset >= 0 && cursorOffset < text.length) cursorOffset,
      if (cursorOffset > 0 && cursorOffset <= text.length) cursorOffset - 1,
    };
    for (final candidate in candidates) {
      final matching = pairs[candidate];
      if (matching != null) {
        activePair.add(candidate);
        activePair.add(matching);
        break;
      }
    }

    return _BracketAnalysis(
      pairs: pairs,
      unmatchedOffsets: unmatched,
      activePair: activePair,
    );
  }
}

final class _BracketHighlightingController extends TextEditingController {
  // Consume identifiers and quoted literals as complete tokens so their digits
  // and operator characters do not get highlighted as separate expressions.
  static final _tokens = RegExp(
    r'''(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?:0[xX][0-9a-fA-F]+(?:[uUlL]*)|0[bB][01]+(?:[uUlL]*)|0[oO][0-7]+|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[fFuUlL]*)|(?:[a-zA-Z_][a-zA-Z_0-9]*)|(?:[+\-*/%&|^~!=<>?:]+)''',
  );

  _BracketAnalysis get bracketAnalysis => _BracketAnalysis.forText(
    text,
    selection.isValid ? selection.extentOffset : text.length,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final analysis = bracketAnalysis;
    if (text.isEmpty) return TextSpan(style: style);
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final literalColor = isDark
        ? const Color(0xFFA6C5B0)
        : const Color(0xFF35634A);
    final operatorColor = isDark
        ? const Color(0xFF9EBBD7)
        : const Color(0xFF345D86);
    final tokenColors = <int, Color>{};
    for (final token in _tokens.allMatches(text)) {
      final value = token.group(0)!;
      final first = value[0];
      final isLiteral =
          RegExp(r'[0-9.]').hasMatch(first) ||
          first == '"' ||
          first == "'" ||
          value == 'true' ||
          value == 'false';
      final isOperator = RegExp(r'[+\-*/%&|^~!=<>?:]').hasMatch(first);
      if (!isLiteral && !isOperator) continue;
      for (var offset = token.start; offset < token.end; offset++) {
        tokenColors[offset] = isLiteral ? literalColor : operatorColor;
      }
    }
    final composing = value.composing;
    final showComposing =
        withComposing &&
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length;
    return TextSpan(
      style: style,
      children: [
        for (var index = 0; index < text.length; index++)
          TextSpan(
            text: text[index],
            style: analysis.unmatchedOffsets.contains(index)
                ? TextStyle(
                    color: colors.error,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.error,
                    decorationStyle: TextDecorationStyle.wavy,
                  )
                : analysis.activePair.contains(index)
                ? TextStyle(
                    color: isDark
                        ? const Color(0xFFA8BED5)
                        : const Color(0xFF294D70),
                    decoration: TextDecoration.underline,
                    decorationColor: isDark
                        ? const Color(0xFF587998)
                        : const Color(0xFF5B7B9B),
                    decorationThickness: 1.5,
                  )
                : TextStyle(
                    color: tokenColors[index],
                    decoration:
                        showComposing &&
                            index >= composing.start &&
                            index < composing.end
                        ? TextDecoration.underline
                        : null,
                  ),
          ),
      ],
    );
  }
}

class HistoryEntry {
  final String expression;
  final String decimal;
  final String hex;
  final String binary;
  final String floatValue;

  const HistoryEntry({
    required this.expression,
    required this.decimal,
    required this.hex,
    required this.binary,
    required this.floatValue,
  });
}

class ProgrammerCalculator extends StatefulWidget {
  const ProgrammerCalculator({super.key});

  @override
  State<ProgrammerCalculator> createState() => _ProgrammerCalculatorState();
}

class _ProgrammerCalculatorState extends State<ProgrammerCalculator> {
  MaterialColor _themeColor = Colors.red;

  @override
  void initState() {
    super.initState();
    // Set dark red as default
    _themeColor = Colors.red;
    if (Colors.red[900] != null) {
      _themeColor = MaterialColor(Colors.red[900]!.value, <int, Color>{
        50: Colors.red[50]!,
        100: Colors.red[100]!,
        200: Colors.red[200]!,
        300: Colors.red[300]!,
        400: Colors.red[400]!,
        500: Colors.red[500]!,
        600: Colors.red[600]!,
        700: Colors.red[700]!,
        800: Colors.red[800]!,
        900: Colors.red[900]!,
      });
    }
  }

  void _updateThemeColor(MaterialColor color) {
    setState(() {
      _themeColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: ThemeData(
          primarySwatch: _themeColor,
          colorScheme: ColorScheme.fromSwatch(primarySwatch: _themeColor),
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),
        darkTheme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.fromSwatch(
            primarySwatch: _themeColor,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade600),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade600),
            ),
          ),
        ),
        home: CalculatorScreen(
          onThemeColorChanged: _updateThemeColor,
          themeColor: _themeColor,
        ),
        scrollBehavior: AppScrollBehavior(),
      ),
    );
  }
}

class CalculatorScreen extends StatefulWidget {
  final bool? showCalcButtonsDesktop;
  final void Function(MaterialColor)? onThemeColorChanged;
  final MaterialColor? themeColor;
  final int initialPanel;
  const CalculatorScreen({
    super.key,
    this.showCalcButtonsDesktop,
    this.onThemeColorChanged,
    this.themeColor,
    this.initialPanel = 0,
  }) : assert(initialPanel >= 0 && initialPanel <= 1);

  @override
  _CalculatorScreenState createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  void _showAddVariableDialog() {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Custom Variable'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Variable Name'),
              ),
              TextField(
                controller: valueController,
                decoration: InputDecoration(labelText: 'Value'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final value = double.tryParse(valueController.text.trim());
                if (name.isNotEmpty && value != null) {
                  // Call FFI to set variable
                  //setCustomVariable(name, value);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Variable "$name" set to $value')),
                  );
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  bool get _isDesktopPlatform => isDesktopPlatform;
  bool get _usesWideLayoutPlatform =>
      _isDesktopPlatform || (!isAndroid && !isIOS);

  late final _BracketHighlightingController _controller;
  final FocusNode _focusNode = FocusNode(); // Added focus node
  late _BracketAnalysis _bracketAnalysis;
  String decimalResult = "";
  String hexResult = "";
  String binaryResult = "";
  String floatResult = "";
  bool hasCalculationError = false;
  List<HistoryEntry> history = [];
  bool showCalcButtons = false;
  bool _expressionExpanded = false;
  double? _expressionEditorHeight;
  String _selectedResultLabel = "Dec";
  _ResultDisplayMode _resultDisplayMode = _ResultDisplayMode.adaptive;

  late int _currentPanel;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();

    _controller = _BracketHighlightingController();
    _bracketAnalysis = _controller.bracketAnalysis;
    _controller.addListener(_updateBracketAnalysis);
    useSystemKeyboardNotifier.addListener(_updateInputMode);

    _currentPanel = widget.initialPanel;
    _pageController = PageController(initialPage: widget.initialPanel);

    // Determine if calculator buttons should be shown
    if (isAndroid || isIOS || kIsWeb) {
      showCalcButtons = true;
    } else {
      showCalcButtons = widget.showCalcButtonsDesktop ?? false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus(); // Set focus to the TextField by default
    });
  }

  @override
  void dispose() {
    useSystemKeyboardNotifier.removeListener(_updateInputMode);
    _controller.removeListener(_updateBracketAnalysis);
    _controller.dispose();
    _focusNode.dispose(); // Dispose of the focus node
    _pageController.dispose();
    super.dispose();
  }

  void _updateInputMode() {
    if (!useSystemKeyboardNotifier.value) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
    setState(() {});
  }

  void _updateBracketAnalysis() {
    final analysis = _controller.bracketAnalysis;
    if (mounted) {
      setState(() {
        _bracketAnalysis = analysis;
      });
    }
  }

  void _clearResult() {
    _controller.clear();

    _focusNode.requestFocus();
  }

  void _focusExpression() {
    if (!_controller.selection.isValid) {
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    _focusNode.requestFocus();
  }

  void _calculateResult() {
    String input = _controller.text;

    //final inputProcessed = preprocessExpression(input);

    try {
      final result = evaluateExpression(input);

      if (result.isError || !result.hasNumericValue) {
        final errMsg =
            result.errorMessage?.trim() ?? getLastErrorMessage().trim();
        final displayError = errMsg.isEmpty ? result.displayText : errMsg;

        setState(() {
          hasCalculationError = true;
          decimalResult = displayError;
          hexResult = "";
          binaryResult = "";
          floatResult = "";
        });
        return;
      }

      final numericValue = result.numericValue!;
      final integerValue = result.integerValue ?? numericValue.truncate();
      final bitWidth = result.bitWidth ?? 32;

      setState(() {
        hasCalculationError = false;
        decimalResult = integerValue.toString();
        hexResult = formatHexResult(
          integerValue,
          bitWidth: bitWidth,
          isSigned: result.isSigned ?? true,
        );
        binaryResult = formatBinaryResult(
          integerValue,
          bitWidth: bitWidth,
          isSigned: result.isSigned ?? true,
        );
        floatResult = formatFloatResult(numericValue);
        history.add(
          HistoryEntry(
            expression: input,
            decimal: decimalResult,
            hex: hexResult,
            binary: binaryResult,
            floatValue: floatResult,
          ),
        );
      });
    } catch (e) {
      final displayError = e.toString();
      setState(() {
        hasCalculationError = true;
        decimalResult = displayError;
        hexResult = "";
        binaryResult = "";
        floatResult = "";
      });
    }

    _focusNode.requestFocus();
  }

  // Panels of calculator buttons
  bool get _mobileKeypad => MediaQuery.sizeOf(context).width < 600;

  List<List<CalcButtonConfig>> get _generalPanel {
    final isMobile = _mobileKeypad;
    return [
      if (isMobile)
        const [
          CalcButtonConfig(
            displayText: 'AC',
            tooltip: 'Clear the entire expression',
          ),
          CalcButtonConfig(
            displayText: 'DEL',
            tooltip: 'Delete the previous character',
          ),
          CalcButtonConfig(displayText: '←', tooltip: 'Move cursor left'),
          CalcButtonConfig(displayText: '→', tooltip: 'Move cursor right'),
        ]
      else
        const [
          CalcButtonConfig(
            displayText: 'AC',
            tooltip: 'Clear the entire expression',
          ),
          CalcButtonConfig(
            displayText: 'DEL',
            tooltip: 'Delete the previous character',
          ),
          CalcButtonConfig(
            displayText: '(',
            tooltip: 'Insert opening parenthesis',
          ),
          CalcButtonConfig(
            displayText: ')',
            tooltip: 'Insert closing parenthesis',
          ),
        ],
      if (isMobile)
        [
          const CalcButtonConfig(
            displayText: '(',
            tooltip: 'Insert opening parenthesis',
          ),
          const CalcButtonConfig(
            displayText: ')',
            tooltip: 'Insert closing parenthesis',
          ),
          CalcButtonConfig(
            displayText: '0x ▾',
            tooltip: 'Hex digits and number prefixes',
            onPressed: (_) => _showOperatorPicker(
              title: 'Hex digits and number prefixes',
              options: [..._hexDigitButtons, ..._prefixButtons],
            ),
          ),
          CalcButtonConfig(
            displayText: '& ▾',
            tooltip: 'Bitwise and logical operators',
            onPressed: (_) => _showOperatorPicker(
              title: 'Bitwise and logical operators',
              options: [
                ..._bitwiseOperators,
                const CalcButtonConfig(displayText: '<<'),
                const CalcButtonConfig(displayText: '>>'),
                ..._logicalOperators,
                const CalcButtonConfig(displayText: '%'),
                const CalcButtonConfig(displayText: 'SPACE', insertText: ' '),
              ],
            ),
          ),
        ],
      [
        const CalcButtonConfig(displayText: '7'),
        const CalcButtonConfig(displayText: '8'),
        const CalcButtonConfig(displayText: '9'),
        const CalcButtonConfig(displayText: '/'),
      ],
      [
        const CalcButtonConfig(displayText: '4'),
        const CalcButtonConfig(displayText: '5'),
        const CalcButtonConfig(displayText: '6'),
        const CalcButtonConfig(displayText: '*'),
      ],
      [
        const CalcButtonConfig(displayText: '1'),
        const CalcButtonConfig(displayText: '2'),
        const CalcButtonConfig(displayText: '3'),
        const CalcButtonConfig(displayText: '-'),
      ],
      [
        const CalcButtonConfig(displayText: '0'),
        const CalcButtonConfig(displayText: '.'),
        const CalcButtonConfig(displayText: '='),
        const CalcButtonConfig(displayText: '+'),
      ],
    ];
  }

  List<CalcButtonConfig> get _bitwiseOperators => const [
    CalcButtonConfig(displayText: '&', tooltip: 'Bitwise AND'),
    CalcButtonConfig(displayText: '|', tooltip: 'Bitwise OR'),
    CalcButtonConfig(displayText: '^', tooltip: 'Bitwise XOR'),
    CalcButtonConfig(displayText: '~', tooltip: 'Bitwise NOT'),
  ];

  List<CalcButtonConfig> get _logicalOperators => const [
    CalcButtonConfig(displayText: '&&', tooltip: 'Logical AND'),
    CalcButtonConfig(displayText: '||', tooltip: 'Logical OR'),
    CalcButtonConfig(displayText: '!', tooltip: 'Logical NOT'),
    CalcButtonConfig(displayText: '!=', tooltip: 'Not equal comparison'),
  ];

  List<CalcButtonConfig> get _hexDigitButtons => const [
    CalcButtonConfig(displayText: 'A', tooltip: 'Hexadecimal digit A'),
    CalcButtonConfig(displayText: 'B', tooltip: 'Hexadecimal digit B'),
    CalcButtonConfig(displayText: 'C', tooltip: 'Hexadecimal digit C'),
    CalcButtonConfig(displayText: 'D', tooltip: 'Hexadecimal digit D'),
    CalcButtonConfig(displayText: 'E', tooltip: 'Hexadecimal digit E'),
    CalcButtonConfig(displayText: 'F', tooltip: 'Hexadecimal digit F'),
  ];

  List<List<CalcButtonConfig>> get _defaultProgrammerPanel => [
    [..._hexDigitButtons.take(4)],
    [..._hexDigitButtons.skip(4), ..._bitwiseOperators.take(2)],
    [..._bitwiseOperators.skip(2), ..._logicalOperators.take(2)],
    [..._logicalOperators.skip(2)],
    [
      const CalcButtonConfig(displayText: '<<', tooltip: 'Shift left'),
      const CalcButtonConfig(displayText: '>>', tooltip: 'Shift right'),
      const CalcButtonConfig(displayText: 'MOD', tooltip: 'Modulo operation'),
      const CalcButtonConfig(displayText: '%', tooltip: 'Percentage operator'),
    ],
    [const CalcButtonConfig(displayText: 'POW', tooltip: 'Power function')],
    [
      const CalcButtonConfig(displayText: '0x', tooltip: 'Hexadecimal prefix'),
      const CalcButtonConfig(displayText: '0b', tooltip: 'Binary prefix'),
      const CalcButtonConfig(displayText: '0o', tooltip: 'Octal prefix'),
      const CalcButtonConfig(
        displayText: 'ANS',
        tooltip: 'Reuse the previous answer',
      ),
    ],
  ];

  List<CalcButtonConfig> get _prefixButtons => const [
    CalcButtonConfig(displayText: '0x', tooltip: 'Hexadecimal prefix'),
    CalcButtonConfig(displayText: '0b', tooltip: 'Binary prefix'),
    CalcButtonConfig(displayText: '0o', tooltip: 'Octal prefix'),
  ];

  List<List<CalcButtonConfig>> _compactProgrammerPanel() {
    return [
      [..._hexDigitButtons.take(4)],
      [..._hexDigitButtons.skip(4), ..._prefixButtons.take(2)],
      [
        ..._prefixButtons.skip(2),
        const CalcButtonConfig(
          displayText: 'ANS',
          tooltip: 'Reuse the previous answer',
        ),
        ..._bitwiseOperators.take(2),
      ],
      [..._bitwiseOperators.skip(2)],
      [
        const CalcButtonConfig(displayText: '<<', tooltip: 'Shift left'),
        const CalcButtonConfig(displayText: '>>', tooltip: 'Shift right'),
        const CalcButtonConfig(displayText: 'MOD', tooltip: 'Modulo operation'),
        const CalcButtonConfig(
          displayText: '%',
          tooltip: 'Percentage operator',
        ),
      ],
      [
        const CalcButtonConfig(displayText: 'POW', tooltip: 'Power function'),
        const CalcButtonConfig(displayText: '&&', tooltip: 'Logical AND'),
        const CalcButtonConfig(displayText: '||', tooltip: 'Logical OR'),
        const CalcButtonConfig(
          displayText: '!=',
          tooltip: 'Not equal comparison',
        ),
      ],
    ];
  }

  List<List<List<CalcButtonConfig>>> _buildButtonPanels(bool isCompactLayout) {
    final programmerPanel = isCompactLayout
        ? _compactProgrammerPanel()
        : _defaultProgrammerPanel;
    if (_mobileKeypad) {
      programmerPanel.insert(0, _generalPanel.first);
      programmerPanel.add(const [
        CalcButtonConfig(
          displayText: '(',
          tooltip: 'Insert opening parenthesis',
        ),
        CalcButtonConfig(
          displayText: ')',
          tooltip: 'Insert closing parenthesis',
        ),
        CalcButtonConfig(displayText: 'SPACE', insertText: ' '),
        CalcButtonConfig(displayText: '=', tooltip: 'Calculate'),
      ]);
    }
    return [_generalPanel, programmerPanel];
  }

  List<CalcButtonConfig> get _wideProgrammerButtons => [
    ..._hexDigitButtons,
    ..._prefixButtons,
    const CalcButtonConfig(
      displayText: 'ANS',
      tooltip: 'Reuse the previous answer',
    ),
    ..._bitwiseOperators,
    const CalcButtonConfig(displayText: '<<', tooltip: 'Shift left'),
    const CalcButtonConfig(displayText: '>>', tooltip: 'Shift right'),
    const CalcButtonConfig(displayText: 'MOD', tooltip: 'Modulo operation'),
    const CalcButtonConfig(displayText: '%', tooltip: 'Percentage operator'),
    const CalcButtonConfig(displayText: 'POW', tooltip: 'Power function'),
    ..._logicalOperators,
  ];

  // Page names for selector
  final List<String> pageNames = ['General', 'Programmer'];

  // Widget for page selector buttons
  Widget buildPageSelector() {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final inactiveBackground = isDark
        ? const Color(0xFF3F3F3F)
        : const Color(0xFFE9E6EC);
    final inactiveForeground = isDark ? Colors.white : const Color(0xFF27232B);
    const inactiveBorder = Color(0xFF8A858D);
    final selectorButtons = <Widget>[];
    for (var index = 0; index < pageNames.length; index++) {
      if (index > 0) {
        selectorButtons.add(const SizedBox(width: 8));
      }
      final isSelected = _currentPanel == index;
      selectorButtons.add(
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isSelected ? colors.primary : inactiveBackground,
              foregroundColor: isSelected
                  ? colors.onPrimary
                  : inactiveForeground,
              elevation: isSelected ? 2 : 0,
              minimumSize: const Size.fromHeight(40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.1,
              ),
              animationDuration: const Duration(milliseconds: 110),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? colors.primary : inactiveBorder,
                ),
              ),
            ),
            onPressed: () {
              _pageController.animateToPage(
                index,
                duration: Duration(milliseconds: 300),
                curve: Curves.ease,
              );
            },
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    const Icon(Icons.check, size: 17),
                    const SizedBox(width: 6),
                  ],
                  Text(pageNames[index]),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: selectorButtons,
    );
  }

  Widget buildCalcButtonsPageView(
    List<List<List<CalcButtonConfig>>> buttonPanels,
    bool isCompactLayout,
  ) {
    return Column(
      children: [
        buildPageSelector(),
        const SizedBox(height: 8),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: buttonPanels.length,
            onPageChanged: (index) {
              setState(() {
                _currentPanel = index;
              });
            },
            itemBuilder: (context, index) {
              return buildCalcButtonsPanel(
                buttonPanels[index],
                isCompactLayout: isCompactLayout,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        CalcPageIndicator(
          pageCount: buttonPanels.length,
          currentPage: _currentPanel,
          activeColor: widget.themeColor ?? Colors.red,
          inactiveColor: Colors.grey,
          onDotTapped: (index) {
            _pageController.animateToPage(
              index,
              duration: Duration(milliseconds: 300),
              curve: Curves.ease,
            );
          },
        ),
      ],
    );
  }

  Widget buildWideCalcButtonsBoard() {
    final programmerButtons = _wideProgrammerButtons;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useMergedBoard = constraints.maxWidth >= 720;
        if (!useMergedBoard) {
          return buildCalcButtonsPageView(_buildButtonPanels(false), false);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 376,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'General',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  buildCalcButtonsPanel(
                    _generalPanel,
                    isCompactLayout: false,
                    desktopButtonWidth: 86,
                    desktopButtonHeight: 62,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Programmer',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: programmerButtons.map((button) {
                      final isLongLabel = button.displayText.length >= 3;
                      return buildStandaloneCalcButton(
                        button,
                        width: isLongLabel ? 72 : 56,
                        height: 44,
                        fontSize: isLongLabel ? 15 : 17,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showOperatorPicker({
    required String title,
    required List<CalcButtonConfig> options,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((option) {
                    return ElevatedButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _handleCalcButtonTap(option);
                      },
                      child: Text(option.displayText),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _reuseHistoryEntry(HistoryEntry entry) {
    _controller.text = entry.expression;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _focusNode.requestFocus();
  }

  void _openHistorySheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'History',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close history',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: history.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No calculations yet.\nSuccessful results will appear here during this session.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final entry = history[history.length - 1 - index];
                            return ListTile(
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                _reuseHistoryEntry(entry);
                              },
                              title: Text(entry.expression),
                              subtitle: Text(
                                'Dec: ${entry.decimal}\nHex: ${entry.hex}\nBin: ${entry.binary}\nFloat: ${entry.floatValue}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.content_paste),
                                    tooltip: 'Reuse expression',
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _reuseHistoryEntry(entry);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy),
                                    tooltip: 'Copy decimal result',
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: entry.decimal),
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text('Decimal copied'),
                                            ),
                                          );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(height: 8),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _moveCursor(int delta) {
    final text = _controller.text;
    final selection = _controller.selection;
    final baseOffset = selection.baseOffset == -1
        ? text.length
        : selection.baseOffset;
    final extentOffset = selection.extentOffset == -1
        ? text.length
        : selection.extentOffset;
    final newOffset = (delta.isNegative ? extentOffset : baseOffset) + delta;
    final clamped = newOffset.clamp(0, text.length);
    _controller.selection = TextSelection.collapsed(offset: clamped);
    _focusNode.requestFocus();
  }

  void _handleCalcButtonTap(CalcButtonConfig button) {
    final label = button.displayText;
    if (label == '←') {
      _moveCursor(-1);
      return;
    }
    if (label == '→') {
      _moveCursor(1);
      return;
    }
    if (label == '=' || label == 'ANS') {
      _calculateResult();
      return;
    }

    if (label == 'AC') {
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }

    if (label == 'DEL' || label == '<' || label == '⌫') {
      if (_controller.text.isEmpty) {
        return;
      }
      final text = _controller.text;
      final selection = _controller.selection;
      if (selection.start != selection.end) {
        final newText = text.replaceRange(selection.start, selection.end, '');
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(
          offset: selection.start,
        );
      } else if (selection.start > 0) {
        final newText = text.replaceRange(
          selection.start - 1,
          selection.start,
          '',
        );
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(
          offset: selection.start - 1,
        );
      }
      _focusNode.requestFocus();
      return;
    }

    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, text.length)
        : start;
    final newText = text.replaceRange(start, end, button.insertText);
    final cursorOffset = start + button.insertText.length;

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
    _focusNode.requestFocus();
  }

  _CalcButtonRole _calcButtonRole(CalcButtonConfig button) {
    final label = button.displayText;
    if (label == '=') {
      return _CalcButtonRole.equals;
    }
    if (label == 'AC') {
      return _CalcButtonRole.destructive;
    }
    if (const {'DEL', '←', '→', 'SPACE'}.contains(label)) {
      return _CalcButtonRole.utility;
    }
    if (RegExp(r'^\d$').hasMatch(label) || label == '.') {
      return _CalcButtonRole.number;
    }
    if (const {'+', '-', '*', '/', '(', ')'}.contains(label)) {
      return _CalcButtonRole.operator;
    }
    return _CalcButtonRole.programmer;
  }

  ButtonStyle _calcButtonStyle(BuildContext context, CalcButtonConfig button) {
    final colors = Theme.of(context).colorScheme;
    final role = _calcButtonRole(button);
    final isDark = colors.brightness == Brightness.dark;
    final (background, foreground) = switch (role) {
      _CalcButtonRole.number => (const Color(0xFF454545), Colors.white),
      _CalcButtonRole.operator => (
        isDark ? const Color(0xFF5BE7CF) : const Color(0xFFC9F9ED),
        const Color(0xFF10241F),
      ),
      _CalcButtonRole.programmer => (
        isDark ? const Color(0xFF4B435B) : const Color(0xFFE6DCF7),
        isDark ? Colors.white : const Color(0xFF2A2038),
      ),
      _CalcButtonRole.utility => (const Color(0xFF4A4A4A), Colors.white),
      _CalcButtonRole.destructive => (
        isDark ? const Color(0xFFDC3030) : const Color(0xFFFFDED9),
        isDark ? Colors.white : const Color(0xFF8C1810),
      ),
      _CalcButtonRole.equals => (colors.primary, colors.onPrimary),
    };

    final hoverBackground = Color.alphaBlend(
      foreground.withValues(alpha: 0.08),
      background,
    );
    final pressedBackground = Color.alphaBlend(
      foreground.withValues(alpha: 0.16),
      background,
    );

    return FilledButton.styleFrom(
      foregroundColor: foreground,
      shadowColor: colors.shadow.withValues(alpha: 0.22),
      minimumSize: const Size(52, 48),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      animationDuration: const Duration(milliseconds: 100),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return pressedBackground;
        }
        if (states.contains(WidgetState.hovered)) {
          return hoverBackground;
        }
        return background;
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return 0;
        }
        if (states.contains(WidgetState.hovered)) {
          return role == _CalcButtonRole.equals ? 3 : 2;
        }
        return role == _CalcButtonRole.equals ? 2 : 1;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        final isFocused = states.contains(WidgetState.focused);
        return BorderSide(
          color: foreground.withValues(
            alpha: isFocused ? 0.72 : (isDark ? 0.34 : 0.28),
          ),
          width: isFocused ? 2 : 1,
        );
      }),
    );
  }

  Widget buildStandaloneCalcButton(
    CalcButtonConfig button, {
    required double width,
    required double height,
    required double fontSize,
  }) {
    Widget calcButton = FilledButton(
      style: _calcButtonStyle(context, button),
      onPressed: () {
        if (button.onPressed != null) {
          button.onPressed!(context);
        } else {
          _handleCalcButtonTap(button);
        }
      },
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          button.displayText,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
        ),
      ),
    );

    if (_isDesktopPlatform && (button.tooltip?.isNotEmpty ?? false)) {
      calcButton = Tooltip(message: button.tooltip!, child: calcButton);
    }

    return SizedBox(
      width: width,
      height: height,
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: calcButton,
      ),
    );
  }

  Widget buildCalcButtonsPanel(
    List<List<CalcButtonConfig>> rows, {
    required bool isCompactLayout,
    double desktopButtonWidth = 88,
    double desktopButtonHeight = 68,
  }) {
    final columnCount = rows.fold<int>(
      0,
      (max, row) => math.max(max, row.length),
    );
    final rowCount = rows.length;
    final effectiveColumnCount = columnCount == 0 ? 1 : columnCount;
    final effectiveRowCount = rowCount == 0 ? 1 : rowCount;

    final paddedRows = rows
        .map<List<CalcButtonConfig?>>(
          (row) => row.length == columnCount
              ? row.cast<CalcButtonConfig?>()
              : [
                  ...row,
                  ...List<CalcButtonConfig?>.filled(
                    columnCount - row.length,
                    null,
                  ),
                ],
        )
        .toList();

    final flattenedButtons = paddedRows.expand((row) => row).toList();
    final isDesktopPlatform = _isDesktopPlatform;

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : columnCount * desktopButtonWidth;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : rowCount * desktopButtonHeight;

        final usableWidth = width - spacing * (effectiveColumnCount - 1);
        final usableHeight = height - spacing * (effectiveRowCount - 1);
        final cellWidth = usableWidth / effectiveColumnCount;
        // A taller editor can leave little room for the keypad. Keep keys
        // usable and scroll the grid instead of producing tiny/negative cells.
        final cellHeight = math.max(44.0, usableHeight / effectiveRowCount);
        final aspectRatio = cellHeight > 0 ? cellWidth / cellHeight : 1.1;
        final double baseFontSize = cellHeight > 0
            ? math.max(14.0, math.min(cellHeight * 0.35, 22.0))
            : 18.0;

        Widget buildButtonCell(
          CalcButtonConfig? button, {
          required double width,
          required double height,
          required double fontSize,
        }) {
          if (button == null) {
            return SizedBox(width: width, height: height);
          }

          Widget calcButton = FilledButton(
            style: _calcButtonStyle(context, button),
            onPressed: () {
              if (button.onPressed != null) {
                button.onPressed!(context);
              } else {
                _handleCalcButtonTap(button);
              }
            },
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                button.displayText,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );

          if (isDesktopPlatform && (button.tooltip?.isNotEmpty ?? false)) {
            calcButton = Tooltip(message: button.tooltip!, child: calcButton);
          }

          return SizedBox(
            width: width,
            height: height,
            child: Focus(
              canRequestFocus: false,
              descendantsAreFocusable: false,
              child: calcButton,
            ),
          );
        }

        if (isDesktopPlatform && !isCompactLayout) {
          final desktopPanelWidth =
              effectiveColumnCount * desktopButtonWidth +
              math.max(0, effectiveColumnCount - 1) * spacing;

          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: desktopPanelWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(paddedRows.length, (rowIndex) {
                  final row = paddedRows[rowIndex];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: rowIndex == paddedRows.length - 1 ? 0 : spacing,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int index = 0; index < row.length; index++) ...[
                          if (index > 0) const SizedBox(width: spacing),
                          buildButtonCell(
                            row[index],
                            width: desktopButtonWidth,
                            height: desktopButtonHeight,
                            fontSize: 20,
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ),
            ),
          );
        }

        return GridView.builder(
          itemCount: flattenedButtons.length,
          shrinkWrap: true,
          physics:
              cellHeight * effectiveRowCount +
                      spacing * (effectiveRowCount - 1) >
                  height
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveColumnCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            return buildButtonCell(
              flattenedButtons[index],
              width: cellWidth,
              height: cellHeight,
              fontSize: baseFontSize,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final useWideLayout = _usesWideLayoutPlatform;
    final adaptiveResultsExpanded =
        useWideLayout || (size.width >= 360 && size.height >= 760);
    final bool useCompactResults = switch (_resultDisplayMode) {
      _ResultDisplayMode.adaptive => !adaptiveResultsExpanded,
      _ResultDisplayMode.expanded => false,
      _ResultDisplayMode.compact => true,
    };
    final bool useCompactButtons =
        // The merged board needs 720px plus the body's horizontal padding.
        size.width < 752 || size.height < 720 || !useWideLayout;
    final availableHeight =
        size.height - MediaQuery.viewInsetsOf(context).bottom;
    // Reserve space for the results, window chrome, keypad selector and at
    // least one usable row of keys. Remaining keypad rows can scroll.
    final reservedHeight = showCalcButtons
        ? (useCompactResults ? 400.0 : 520.0)
        : 200.0;
    final maxEditorHeight = math
        .min(availableHeight * 0.6, availableHeight - reservedHeight)
        .clamp(80.0, 480.0)
        .toDouble();
    final defaultEditorHeight = (availableHeight * 0.22)
        .clamp(80.0, math.min(176.0, maxEditorHeight))
        .toDouble();
    final editorHeight = (_expressionEditorHeight ?? defaultEditorHeight).clamp(
      80.0,
      maxEditorHeight,
    );
    void resizeEditor(double delta) {
      setState(() {
        _expressionEditorHeight =
            ((_expressionEditorHeight ?? defaultEditorHeight).clamp(
                      80.0,
                      maxEditorHeight,
                    ) +
                    delta)
                .clamp(80.0, maxEditorHeight)
                .toDouble();
      });
    }

    final buttonPanels = _buildButtonPanels(useCompactButtons);
    final Widget inlineCalcButton = IconButton.filled(
      icon: const Icon(Icons.calculate_outlined),
      tooltip: 'Calculate',
      onPressed: _calculateResult,
    );

    final Widget inlineClearButton = IconButton.filledTonal(
      icon: const Icon(Icons.delete_sweep_outlined),
      tooltip: 'Clear expression',
      onPressed: _clearResult,
    );

    final expressionBorderColor = _bracketAnalysis.hasError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF8A858D)
        : const Color(0xFF6F6A73);
    final expressionBorder = OutlineInputBorder(
      borderSide: BorderSide(color: expressionBorderColor),
    );

    Widget buildResultField(
      String label,
      String value, {
      bool compact = false,
      bool isError = false,
      bool showLabel = true,
      Widget? labelAction,
    }) {
      final colorScheme = Theme.of(context).colorScheme;
      final resultBorderColor = colorScheme.brightness == Brightness.dark
          ? const Color(0xFF8A858D)
          : const Color(0xFF8A858D);
      final border = OutlineInputBorder(
        borderSide: BorderSide(
          color: isError ? colorScheme.error : resultBorderColor,
        ),
      );

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            if (showLabel)
              SizedBox(
                width: compact ? 90 : 110,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: compact ? 14 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (labelAction != null) labelAction,
                  ],
                ),
              ),
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: compact ? 6 : 8,
                    horizontal: compact ? 6 : 8,
                  ),
                  border: border,
                  enabledBorder: border,
                ),
                child: SelectableText(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compact ? 14 : 16,
                    color: isError ? colorScheme.error : null,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.copy, size: 20),
              tooltip: 'Copy',
              onPressed: value.isNotEmpty && value != 'Error'
                  ? () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied to clipboard')),
                      );
                    }
                  : null,
            ),
          ],
        ),
      );
    }

    Widget buildResultsSection(bool isCompactLayout) {
      final results = <String, String>{
        "Dec": decimalResult,
        "Hex": hexResult,
        "Bin": binaryResult,
        "Float": floatResult,
      };

      if (!isCompactLayout) {
        return Column(
          children: [
            buildResultField(
              "Decimal",
              decimalResult,
              isError: hasCalculationError,
              labelAction: IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.unfold_less, size: 18),
                tooltip: 'Show one result unit',
                onPressed: () {
                  setState(() {
                    _resultDisplayMode = _ResultDisplayMode.compact;
                  });
                },
              ),
            ),
            buildResultField("Hexadecimal", hexResult),
            buildResultField("Binary", binaryResult),
            buildResultField("Floating Point", floatResult),
          ],
        );
      }

      final selectedValue = results[_selectedResultLabel] ?? "";

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                results.keys.map<Widget>((label) {
                  return ChoiceChip(
                    label: Text(label),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selected: _selectedResultLabel == label,
                    onSelected: (_) {
                      setState(() {
                        _selectedResultLabel = label;
                      });
                    },
                  );
                }).toList()..add(
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.unfold_more),
                    tooltip: 'Show all result units',
                    onPressed: () {
                      setState(() {
                        _resultDisplayMode = _ResultDisplayMode.expanded;
                      });
                    },
                  ),
                ),
          ),
          const SizedBox(height: 4),
          buildResultField(
            _selectedResultLabel,
            selectedValue,
            compact: true,
            isError: hasCalculationError && _selectedResultLabel == "Dec",
            showLabel: false,
          ),
        ],
      );
    }

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final headerActions = [
      WindowChromeActionButton(
        icon: Icons.history,
        tooltip: 'History',
        onPressed: _openHistorySheet,
      ),
      if (enableCustomVariables)
        WindowChromeActionButton(
          icon: Icons.add,
          tooltip: 'Add Variable',
          onPressed: _showAddVariableDialog,
        ),
      WindowChromeActionButton(
        icon: Icons.help_outline,
        tooltip: 'Help',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  HelpScreen(themeColor: widget.themeColor ?? Colors.red),
            ),
          );
        },
      ),
      WindowChromeActionButton(
        icon: Icons.code,
        tooltip: 'Source code (AGPLv3)',
        onPressed: () async {
          await launchUrl(_sourceCodeUri, mode: LaunchMode.externalApplication);
        },
      ),
      WindowChromeActionButton(
        icon: Icons.dialpad_outlined,
        tooltip: showCalcButtons
            ? 'Hide calculator buttons'
            : 'Show calculator buttons',
        onPressed: () {
          setState(() {
            showCalcButtons = !showCalcButtons;
          });
        },
      ),
      WindowChromeActionButton(
        icon: isDarkTheme
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
        tooltip: isDarkTheme ? 'Switch to light theme' : 'Switch to dark theme',
        onPressed: () async {
          final mode = isDarkTheme ? ThemeMode.light : ThemeMode.dark;
          themeModeNotifier.value = mode;
          await saveThemeMode(mode);
        },
      ),
      WindowChromeActionButton(
        icon: Icons.settings,
        tooltip: 'Settings',
        onPressed: () async {
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => SettingsDialog(
              themeColor: widget.themeColor ?? Colors.red,
              showCalcButtonsDesktop: showCalcButtons,
            ),
          );
          if (result is bool) {
            setState(() {
              showCalcButtons = result;
            });
          }
        },
      ),
    ];

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            _CalculateExpressionIntent(),
        SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _CalculateExpressionIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _FocusExpressionIntent(),
      },
      child: Actions(
        actions: {
          _CalculateExpressionIntent:
              CallbackAction<_CalculateExpressionIntent>(
                onInvoke: (_) {
                  _calculateResult();
                  return null;
                },
              ),
          _FocusExpressionIntent: CallbackAction<_FocusExpressionIntent>(
            onInvoke: (_) {
              _focusExpression();
              return null;
            },
          ),
        },
        child: FramelessWindowResizeFrame(
          child: Scaffold(
            appBar: WindowChromeHeader(
              title: const AppTitleLabel(),
              backgroundColor: Theme.of(context).colorScheme.surface,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              actions: [
                MenuAnchor(
                  menuChildren: headerActions.map((action) {
                    final button = action;
                    return MenuItemButton(
                      leadingIcon: Icon(button.icon),
                      onPressed: button.onPressed,
                      child: Text(button.tooltip),
                    );
                  }).toList(),
                  builder: (context, controller, child) =>
                      WindowChromeActionButton(
                        icon: Icons.menu,
                        tooltip: 'Application menu',
                        onPressed: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                      ),
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: _expressionExpanded ? editorHeight : 56,
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  decoration: InputDecoration(
                                    border: expressionBorder,
                                    enabledBorder: expressionBorder,
                                    focusedBorder: expressionBorder,
                                    floatingLabelStyle: TextStyle(
                                      color: expressionBorderColor,
                                    ),
                                    labelText: "Enter Expression",
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_bracketAnalysis.hasError ||
                                            _bracketAnalysis.hasActivePair)
                                          Tooltip(
                                            message:
                                                _bracketAnalysis.statusMessage,
                                            child: Icon(
                                              _bracketAnalysis.hasError
                                                  ? Icons.error_outline
                                                  : Icons.link,
                                              color: expressionBorderColor,
                                            ),
                                          ),
                                        if (_expressionExpanded)
                                          IconButton(
                                            tooltip: 'Insert newline',
                                            icon: const Icon(
                                              Icons.keyboard_return,
                                            ),
                                            onPressed: () =>
                                                _handleCalcButtonTap(
                                                  const CalcButtonConfig(
                                                    displayText: 'Newline',
                                                    insertText: '\n',
                                                  ),
                                                ),
                                          ),
                                        IconButton(
                                          tooltip: _expressionExpanded
                                              ? 'Collapse expression editor'
                                              : 'Expand expression editor',
                                          icon: Icon(
                                            _expressionExpanded
                                                ? Icons.unfold_less
                                                : Icons.unfold_more,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _expressionExpanded =
                                                  !_expressionExpanded;
                                            });
                                            _focusNode.requestFocus();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  style: TextStyle(fontSize: 20),
                                  maxLines: _expressionExpanded ? null : 1,
                                  expands: _expressionExpanded,
                                  textAlignVertical: _expressionExpanded
                                      ? TextAlignVertical.top
                                      : TextAlignVertical.center,
                                  textInputAction: _expressionExpanded
                                      ? TextInputAction.newline
                                      : TextInputAction.done,
                                  keyboardType: useSystemKeyboardNotifier.value
                                      ? (_expressionExpanded
                                            ? TextInputType.multiline
                                            : TextInputType.text)
                                      : TextInputType.none,
                                  showCursor: true,
                                  selectAllOnFocus: false,
                                  enableInteractiveSelection: true,
                                  onTap: () {
                                    if (isAndroid) {
                                      // Keep focus so user can use app keypad
                                      _focusNode.requestFocus();
                                    }
                                  },
                                  onSubmitted: _expressionExpanded
                                      ? null
                                      : (_) => _calculateResult(),
                                ),
                              ),
                              if (!_mobileKeypad || !showCalcButtons) ...[
                                inlineCalcButton,
                                inlineClearButton,
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.arrow_left),
                                  tooltip: 'Move cursor left',
                                  onPressed: () => _moveCursor(-1),
                                ),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.arrow_right),
                                  tooltip: 'Move cursor right',
                                  onPressed: () => _moveCursor(1),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_expressionExpanded)
                          TextFieldTapRegion(
                            child: Semantics(
                              label: 'Expression editor height',
                              value: '${editorHeight.round()} pixels',
                              increasedValue: editorHeight < maxEditorHeight
                                  ? '${math.min(editorHeight + 24, maxEditorHeight).round()} pixels'
                                  : null,
                              decreasedValue: editorHeight > 80
                                  ? '${math.max(editorHeight - 24, 80).round()} pixels'
                                  : null,
                              onIncrease: editorHeight < maxEditorHeight
                                  ? () => resizeEditor(24)
                                  : null,
                              onDecrease: editorHeight > 80
                                  ? () => resizeEditor(-24)
                                  : null,
                              child: Tooltip(
                                message: 'Drag to resize expression editor',
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeUpDown,
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'expression-resize-handle',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onVerticalDragUpdate: (details) =>
                                        resizeEditor(details.delta.dy),
                                    child: SizedBox(
                                      height: 24,
                                      width: double.infinity,
                                      child: Center(
                                        child: Container(
                                          width: 36,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outlineVariant,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 16),
                        if (showCalcButtons)
                          Align(
                            alignment: Alignment.topLeft,
                            child: buildResultsSection(useCompactResults),
                          )
                        else
                          Flexible(
                            fit: FlexFit.tight,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: buildResultsSection(useCompactResults),
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (showCalcButtons) ...[
                          Expanded(
                            child: useCompactButtons
                                ? buildCalcButtonsPageView(
                                    buttonPanels,
                                    useCompactButtons,
                                  )
                                : SingleChildScrollView(
                                    child: buildWideCalcButtonsBoard(),
                                  ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
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
