# Accessibility

PCalc Express provides explicit semantics for the expression editor, formatted
results, copy controls, calculator keys, application actions, window controls,
and the multiline resize handle. Symbol keys use spoken operation names such as
“Divide”, “Multiply”, and “Decimal point”. Result nodes expose both their unit
and current value.

Widget-level coverage lives in `test/accessibility_test.dart`. Run it with:

```sh
flutter test test/accessibility_test.dart
```

## Linux and AT-SPI

Linux accessibility must be tested through AT-SPI, not inferred from Flutter
widget semantics. Build a Linux debug bundle, then test either runner:

```sh
export AT_SPI_VALIDATOR="$HOME/bin/validate_atspi_export.py"
tools/test_linux_accessibility.sh build/linux-gtk4/x64/debug/bundle/pcalc_express
tools/test_linux_accessibility.sh build/linux/x64/debug/bundle/pcalc_express
```

The test detects GTK3 or GTK4, enables the appropriate accessibility bridge,
verifies a non-trivial tree, and requires named expression, calculation, and
result nodes. `GTK_A11Y=always` is not a valid GTK4 backend value.

## GTK4 engine finding

Tested with Flutter framework revision
`280e8df0ab1f91a87078de00705b61b8d47d8719` and engine artifact
`61dae0cb8f6752dae2404a6c142737f04df2592e` on Wayland.

The engine exports the tree only after the AT-SPI backend is active. Before the
app supplied explicit labels, icon buttons built with Flutter `Tooltip` reached
AT-SPI as unnamed `button` nodes with the tooltip in `description`. For example,
the Calculate control was exported as:

```text
- button: <unnamed> [description: Calculate]
```

Expected behavior is a usable accessible name, because screen readers and
automation commonly locate controls by role and name. The app now supplies
explicit labels as a portable workaround. The focused engine fix should promote
a non-empty tooltip to the GTK accessible label when an actionable semantics
node has no label, while avoiding a duplicated description. That change belongs
in the GTK4 accessibility bridge with a native-tree regression test; it should
remain separate from this app integration.

## GTK3 comparison and engine finding

The same semantic widgets and assertions pass with the GTK4 runner. With the
stock Flutter GTK3 runner on Fedora 44 and AT-SPI/ATK 2.60.6, the application
does not register an accessible tree and emits:

```text
Atk-CRITICAL: atk_socket_embed: assertion 'plug_id != NULL' failed
```

Explicitly loading `gail:atk-bridge`, restarting the user AT-SPI service, and
providing its bus address do not resolve the failure. Other applications remain
visible to AT-SPI and the GTK4 build passes in the same session. The failure is
therefore below the app's Flutter semantics: the GTK3 runner calls
`atk_plug_get_id(view_accessible)` and passes a null ID to `atk_socket_embed`
before the app can be discovered by assistive technology.

Keep the GTK3 native check separate and non-blocking until this runner defect is
fixed upstream. An upstream report should include the Flutter revision, Fedora
and AT-SPI package versions, the command above as a minimal reproduction, the
critical warning, and the successful GTK4 control result.
