import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pcalc_express/platform_capabilities.dart';

const double _chromeHeaderHeight = 32;
const double _chromeControlButtonSize = 28;

class WindowChromeController {
  static const MethodChannel _channel = MethodChannel('app/window_style');
  static final ValueNotifier<bool> useLinuxSystemDecorations = ValueNotifier(
    false,
  );

  static bool get supportsLinuxSystemDecorations => isLinux;
  static bool get useCustomWindowChrome =>
      !(isLinux && useLinuxSystemDecorations.value);

  static Future<void> setLinuxSystemDecorations(bool enabled) async {
    useLinuxSystemDecorations.value = enabled;
    if (!supportsLinuxSystemDecorations) {
      return;
    }
    try {
      await _channel.invokeMethod('setUseSystemDecorations', {
        'enabled': enabled,
      });
    } catch (_) {
      // Best-effort native toggle; Flutter UI state still updates.
    }
  }
}

enum WindowResizeEdge {
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  topLeft,
}

class WindowDragController {
  static const MethodChannel _channel = MethodChannel('app/window_drag');
  static final ValueNotifier<bool> isMaximized = ValueNotifier(false);
  static bool _initialWindowStateRequested = false;
  static bool _closeRequested = false;

  static bool get supportsWindowControls => isLinux || isWindows;
  static bool get _supportsDragging => supportsWindowControls;

  static Future<void> startDragging() async {
    if (!_supportsDragging) {
      return;
    }
    try {
      await _channel.invokeMethod('startDrag');
    } catch (_) {
      // Ignore failures to keep the UI responsive if the channel is unavailable.
    }
  }

  static Future<void> startResize(WindowResizeEdge edge) async {
    if (!_supportsDragging) {
      return;
    }
    try {
      await _channel.invokeMethod('startResize', {'edge': edge.name});
    } catch (_) {
      // Ignore failures to keep the UI responsive if the channel is unavailable.
    }
  }

  static Future<void> minimize() async {
    if (!supportsWindowControls) {
      return;
    }
    try {
      await _channel.invokeMethod('minimize');
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }

  static Future<void> toggleMaximize() async {
    if (!supportsWindowControls) {
      return;
    }
    try {
      await _channel.invokeMethod('toggleMaximize');
      await refreshMaximizedState();
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }

  static Future<void> refreshMaximizedState() async {
    if (!supportsWindowControls) {
      return;
    }
    try {
      final maximized = await _channel.invokeMethod<bool>('isMaximized');
      if (maximized != null) {
        isMaximized.value = maximized;
      }
    } catch (_) {
      // Ignore failures; window controls are best-effort.
    }
  }

  static void ensureWindowStateInitialized() {
    if (!supportsWindowControls || _initialWindowStateRequested) {
      return;
    }
    _initialWindowStateRequested = true;
    unawaited(refreshMaximizedState());
  }

  static Future<void> close() async {
    if (!supportsWindowControls || _closeRequested) {
      return;
    }
    _closeRequested = true;
    try {
      await _channel.invokeMethod('close');
    } catch (_) {
      _closeRequested = false;
      // Ignore failures; window controls are best-effort.
    }
  }
}

class FramelessWindowResizeFrame extends StatelessWidget {
  const FramelessWindowResizeFrame({
    super.key,
    required this.child,
    this.resizeBorderThickness = 6,
    this.resizeCornerSize = 18,
    this.topControlsSafeWidth = 160,
    this.topControlsSafeHeight = _chromeHeaderHeight,
  });

  final Widget child;
  final double resizeBorderThickness;
  final double resizeCornerSize;
  final double topControlsSafeWidth;
  final double topControlsSafeHeight;

  @override
  Widget build(BuildContext context) {
    if (!WindowDragController.supportsWindowControls ||
        !WindowChromeController.useCustomWindowChrome) {
      return child;
    }

    return Stack(
      children: [
        Positioned.fill(child: child),
        ..._buildResizeHandles(),
      ],
    );
  }

  List<Widget> _buildResizeHandles() {
    final border = resizeBorderThickness;
    final corner = resizeCornerSize;
    final topRightSafeWidth = topControlsSafeWidth > corner
        ? topControlsSafeWidth
        : corner;
    final rightTopSafeHeight = topControlsSafeHeight > corner
        ? topControlsSafeHeight
        : corner;

    return [
      Positioned(
        left: corner,
        right: topRightSafeWidth,
        top: 0,
        height: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.top,
          cursor: SystemMouseCursors.resizeUp,
        ),
      ),
      Positioned(
        right: 0,
        top: rightTopSafeHeight,
        bottom: corner,
        width: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.right,
          cursor: SystemMouseCursors.resizeRight,
        ),
      ),
      Positioned(
        left: corner,
        right: corner,
        bottom: 0,
        height: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.bottom,
          cursor: SystemMouseCursors.resizeDown,
        ),
      ),
      Positioned(
        left: 0,
        top: corner,
        bottom: corner,
        width: border,
        child: _ResizeHandle(
          edge: WindowResizeEdge.left,
          cursor: SystemMouseCursors.resizeLeft,
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: corner,
        height: corner,
        child: _ResizeHandle(
          edge: WindowResizeEdge.topLeft,
          cursor: SystemMouseCursors.resizeUpLeft,
        ),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        width: corner,
        height: corner,
        child: _ResizeHandle(
          edge: WindowResizeEdge.bottomRight,
          cursor: SystemMouseCursors.resizeDownRight,
        ),
      ),
      Positioned(
        left: 0,
        bottom: 0,
        width: corner,
        height: corner,
        child: _ResizeHandle(
          edge: WindowResizeEdge.bottomLeft,
          cursor: SystemMouseCursors.resizeDownLeft,
        ),
      ),
    ];
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.edge, required this.cursor});

  final WindowResizeEdge edge;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => WindowDragController.startResize(edge),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowDragController._supportsDragging) {
      return child;
    }
    if (!WindowChromeController.useCustomWindowChrome) {
      return child;
    }
    WindowDragController.ensureWindowStateInitialized();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => WindowDragController.toggleMaximize(),
      onPanStart: (_) => WindowDragController.startDragging(),
      child: child,
    );
  }
}

class WindowChromeHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const WindowChromeHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.backgroundColor,
    this.foregroundColor,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(_chromeHeaderHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor =
        backgroundColor ??
        theme.appBarTheme.backgroundColor ??
        theme.colorScheme.surface;
    final onSurface =
        foregroundColor ??
        theme.appBarTheme.foregroundColor ??
        theme.colorScheme.onSurface;

    return Material(
      color: surfaceColor,
      elevation: theme.appBarTheme.elevation ?? 0,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _chromeHeaderHeight,
              child: Row(
                children: [
                  if (leading != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: leading!,
                    ),
                  ],
                  Expanded(
                    child: WindowDragArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DefaultTextStyle(
                                style:
                                    theme.appBarTheme.titleTextStyle ??
                                    theme.textTheme.titleSmall!.copyWith(
                                      color: onSurface,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                child: title,
                              ),
                              if (subtitle != null)
                                DefaultTextStyle(
                                  style:
                                      theme.appBarTheme.toolbarTextStyle ??
                                      theme.textTheme.bodySmall!.copyWith(
                                        color: onSurface,
                                        fontSize: 10,
                                      ),
                                  child: subtitle!,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    IconTheme(
                      data: IconThemeData(color: onSurface),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: actions,
                      ),
                    ),
                  ],
                  if (actions.isNotEmpty) const SizedBox(width: 4),
                  IconTheme(
                    data: IconThemeData(color: onSurface),
                    child: const WindowControlButtons(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WindowControlButtons extends StatelessWidget {
  const WindowControlButtons({super.key});

  @override
  Widget build(BuildContext context) {
    if (!WindowDragController.supportsWindowControls ||
        !WindowChromeController.useCustomWindowChrome) {
      return const SizedBox.shrink();
    }
    WindowDragController.ensureWindowStateInitialized();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowControlButton(
          tooltip: 'Minimize',
          icon: Icons.minimize,
          onPressed: () => WindowDragController.minimize(),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: WindowDragController.isMaximized,
          builder: (context, isMaximized, _) {
            return _WindowControlButton(
              tooltip: isMaximized ? 'Restore' : 'Maximize',
              icon: isMaximized ? Icons.filter_none : Icons.crop_square,
              onPressed: () => WindowDragController.toggleMaximize(),
            );
          },
        ),
        _WindowControlButton(
          tooltip: 'Close',
          icon: Icons.close,
          onPressed: () => WindowDragController.close(),
        ),
      ],
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: IconButton(
          icon: Icon(icon, size: 16),
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: _chromeControlButtonSize,
            height: _chromeControlButtonSize,
          ),
          visualDensity: VisualDensity.compact,
          splashRadius: 16,
        ),
      ),
    );
  }
}

class WindowChromeActionButton extends StatelessWidget {
  const WindowChromeActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: IconButton(
          icon: Icon(icon, size: 16),
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: _chromeControlButtonSize,
            height: _chromeControlButtonSize,
          ),
          visualDensity: VisualDensity.compact,
          splashRadius: 16,
        ),
      ),
    );
  }
}
