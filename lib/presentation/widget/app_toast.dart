import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

enum AppToastKind { error, info, success }

class AppToast {
  AppToast._();

  static final List<_ToastHandle> _live = [];

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message,
      AppToastKind.error,
      duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(context, message, AppToastKind.info, duration);
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(context, message, AppToastKind.success, duration);
  }

  /// Removes every toast currently on screen.
  static void dismissAll() {
    for (final handle in List<_ToastHandle>.of(_live)) {
      handle.remove();
    }
    _live.clear();
  }

  static void _show(
    BuildContext context,
    String message,
    AppToastKind kind,
    Duration duration, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (message.isEmpty) return;
    if (!context.mounted) return;

    OverlayState overlay;
    try {
      overlay = Overlay.of(context, rootOverlay: true);
    } catch (_) {
      return;
    }

    double topInset = 0;
    try {
      topInset = MediaQuery.of(context).padding.top;
    } catch (_) {
      topInset = 0;
    }

    for (final handle in List<_ToastHandle>.of(_live)) {
      handle.remove();
    }
    _live.clear();

    final handle = _ToastHandle();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: topInset + 12,
        left: 12,
        right: 12,
        child: Align(
          alignment: Alignment.topRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _AppToastCard(
              message: message,
              kind: kind,
              duration: duration,
              actionLabel: actionLabel,
              onAction: onAction,
              onClose: () {
                handle.remove();
                _live.remove(handle);
              },
            ),
          ),
        ),
      ),
    );
    handle.entry = entry;
    _live.add(handle);
    overlay.insert(entry);
  }
}

class _ToastHandle {
  OverlayEntry? entry;
  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    try {
      entry?.remove();
    } catch (_) {}
  }
}

Color _kindColor(AppToastKind kind) {
  switch (kind) {
    case AppToastKind.error:
      return HermesColors.rose;
    case AppToastKind.info:
      return HermesColors.electricTeal;
    case AppToastKind.success:
      return HermesColors.emerald;
  }
}

IconData _kindIcon(AppToastKind kind) {
  switch (kind) {
    case AppToastKind.error:
      return Icons.error_outline;
    case AppToastKind.info:
      return Icons.info_outline;
    case AppToastKind.success:
      return Icons.check_circle_outline;
  }
}

class _AppToastCard extends StatefulWidget {
  final String message;
  final AppToastKind kind;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;

  const _AppToastCard({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_AppToastCard> createState() => _AppToastCardState();
}

class _AppToastCardState extends State<_AppToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    if (!mounted) {
      widget.onClose();
      return;
    }
    try {
      await _controller.reverse();
    } catch (_) {}
    widget.onClose();
  }

  void _onActionTap() {
    widget.onAction?.call();
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final kindColor = _kindColor(widget.kind);
    final kindIcon = _kindIcon(widget.kind);
    final maxHeight = MediaQuery.of(context).size.height * 0.35;
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          key: const Key('app_toast'),
          color: HermesColors.cardSurface,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: kindColor, width: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(kindIcon, size: 18, color: kindColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.message,
                            key: const Key('app_toast_message'),
                            style: const TextStyle(
                              color: HermesColors.inkPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (widget.actionLabel != null)
                          TextButton(
                            key: const Key('app_toast_action'),
                            style: TextButton.styleFrom(
                              foregroundColor: HermesColors.accentTeal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _onActionTap,
                            child: Text(widget.actionLabel!),
                          ),
                        IconButton(
                          key: const Key('app_toast_close'),
                          icon: const Icon(Icons.close),
                          iconSize: 16,
                          color: HermesColors.inkSecondary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _dismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
