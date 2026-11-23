import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import '../services/native_bridge_service.dart';

/// Modern frameless desktop title bar supporting macOS traffic light inset
/// and Windows custom chrome controls (minimize, maximize/restore, close).
class DesktopTitleBar extends StatefulWidget implements PreferredSizeWidget {
  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final double height;

  /// Test overrides for simulating desktop platforms during tests.
  @visibleForTesting
  static bool? debugIsMacOS;
  @visibleForTesting
  static bool? debugIsWindows;

  const DesktopTitleBar({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.height = 38.0,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximizedState();
  }

  Future<void> _checkMaximizedState() async {
    final isMac = DesktopTitleBar.debugIsMacOS ?? (!kIsWeb && Platform.isMacOS);
    final isWin = DesktopTitleBar.debugIsWindows ?? (!kIsWeb && Platform.isWindows);
    if (!isMac && !isWin) return;

    final max = await NativeBridgeService.isWindowMaximized();
    if (mounted && max != _isMaximized) {
      setState(() => _isMaximized = max);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMac = DesktopTitleBar.debugIsMacOS ?? (!kIsWeb && Platform.isMacOS);
    final isWin = DesktopTitleBar.debugIsWindows ?? (!kIsWeb && Platform.isWindows);

    // Non-desktop immunity: 0 height, 0 overhead on mobile & web
    if (!isMac && !isWin) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // macOS: Reserve 78px for native traffic light buttons
          if (isMac) const SizedBox(width: 78.0),

          // Optional leading or branding icon
          if (widget.leading != null) widget.leading!,

          // Draggable area & title
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => NativeBridgeService.windowStartDragging(),
              onDoubleTap: () async {
                await NativeBridgeService.windowMaximize();
                await _checkMaximizedState();
              },
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  if (widget.title != null)
                    widget.title!
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'MultiPad',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),

          if (widget.actions != null) ...widget.actions!,

          // Windows Custom Window Chrome Controls
          if (isWin) ...[
            _WindowButton(
              icon: Icons.remove,
              tooltip: 'Minimize',
              onPressed: () => NativeBridgeService.windowMinimize(),
            ),
            _WindowButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              size: _isMaximized ? 12 : 14,
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
              onPressed: () async {
                await NativeBridgeService.windowMaximize();
                await _checkMaximizedState();
              },
            ),
            _WindowButton(
              icon: Icons.close,
              isClose: true,
              tooltip: 'Close',
              onPressed: () => NativeBridgeService.windowClose(),
            ),
          ],
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;
  final double size;
  final String tooltip;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
    this.size = 14.0,
    required this.tooltip,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hoverColor = widget.isClose
        ? const Color(0xFFE81123)
        : theme.colorScheme.onSurface.withValues(alpha: 0.1);
    final iconColor = (widget.isClose && _isHovered)
        ? Colors.white
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: double.infinity,
            color: _isHovered ? hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.size,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
