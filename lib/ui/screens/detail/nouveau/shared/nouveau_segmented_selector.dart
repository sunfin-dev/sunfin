import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../../util/focus/dpad_keys.dart';
import '../../../../widgets/focus/focusable_wrapper.dart';

class NouveauSegmentedSelector<T> extends StatefulWidget {
  final List<T> values;
  final T? selectedValue;
  final String Function(T value) labelBuilder;
  final Widget? Function(T value)? leadingBuilder;
  final ValueChanged<T> onValueActivated;
  final bool Function()? onNavigateUp;
  final bool Function()? onNavigateDown;
  final bool allowLeftEdgeExit;
  final bool trapRightEdge;
  final bool selectOnFocus;
  final double height;
  final double minimumSegmentWidth;

  const NouveauSegmentedSelector({
    super.key,
    required this.values,
    required this.selectedValue,
    required this.labelBuilder,
    required this.onValueActivated,
    this.leadingBuilder,
    this.onNavigateUp,
    this.onNavigateDown,
    this.allowLeftEdgeExit = false,
    this.trapRightEdge = true,
    this.selectOnFocus = false,
    this.height = 40,
    this.minimumSegmentWidth = 88,
  });

  @override
  State<NouveauSegmentedSelector<T>> createState() =>
      NouveauSegmentedSelectorState<T>();
}

class NouveauSegmentedSelectorState<T>
    extends State<NouveauSegmentedSelector<T>> {
  final Map<T, FocusNode> _focusNodes = {};

  T? _hoveredValue;

  FocusNode _focusNodeFor(T value) {
    return _focusNodes.putIfAbsent(
      value,
      () => FocusNode(
        debugLabel: 'nouveauSegment_${value.toString()}',
        skipTraversal: true,
      ),
    );
  }

  void requestFocusAt(T value) {
    final node = _focusNodeFor(value);

    if (node.canRequestFocus && node.context != null) {
      node.requestFocus();
    }
  }

  void _activate(T value) {
    requestFocusAt(value);

    if (value != widget.selectedValue) {
      widget.onValueActivated(value);
    }
  }

  void _focusAdjacent(int index, int direction) {
    final target = index + direction;

    if (target >= 0 && target < widget.values.length) {
      requestFocusAt(widget.values[target]);
    }
  }

  void _handleFocusChanged(bool focused, T value) {
    if (focused) _reveal(value, animate: true);
    if (focused && widget.selectOnFocus && value != widget.selectedValue) {
      widget.onValueActivated(value);
    }
  }

  /// Sunfin: a show with many seasons runs the row past the screen edge, and
  /// nothing scrolled it, so the focused season sat off screen (user,
  /// 2026-10-23). Keeps [value]'s segment in view.
  void _reveal(T value, {required bool animate}) {
    final segmentContext = _focusNodes[value]?.context;
    if (segmentContext == null || !segmentContext.mounted) return;
    Scrollable.ensureVisible(
      segmentContext,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  /// The selection can also change from outside, e.g. the page opening on an
  /// episode of a late season, so it is brought into view after each layout.
  void _revealSelectedAfterLayout({required bool animate}) {
    final selected = widget.selectedValue;
    if (selected == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(selected, animate: animate);
    });
  }

  @override
  void initState() {
    super.initState();
    _revealSelectedAfterLayout(animate: false);
  }

  @override
  void didUpdateWidget(covariant NouveauSegmentedSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue) {
      _revealSelectedAfterLayout(animate: true);
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = AppColorScheme.onSurface;

    return Container(
      height: widget.height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.045),
        border: Border.all(color: foreground.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Clipped now that it scrolls, or segments scrolled past the edge
        // would draw outside the pill. Focus is drawn inside each segment.
        clipBehavior: Clip.hardEdge,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < widget.values.length; index++)
              _buildSegment(context, index, widget.values[index]),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(BuildContext context, int index, T value) {
    final node = _focusNodeFor(value);
    final selected = value == widget.selectedValue;
    final hovered = value == _hoveredValue;
    final leading = widget.leadingBuilder?.call(value);

    final theme = Theme.of(context);
    final foreground = AppColorScheme.onSurface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (_hoveredValue == value) {
          return;
        }

        setState(() {
          _hoveredValue = value;
        });
      },
      onExit: (_) {
        if (_hoveredValue != value) {
          return;
        }

        setState(() {
          _hoveredValue = null;
        });
      },
      child: FocusableWrapper(
        focusNode: node,
        borderRadius: 16,
        suppressFocusGlow: true,
        disableScale: true,
        semanticLabel: widget.labelBuilder(value),
        onSelect: () {
          _activate(value);
        },
        onKeyEvent: (_, event) {
          if (!event.isActionable) {
            return KeyEventResult.ignored;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final callback = widget.onNavigateUp;

            if (callback == null) {
              return KeyEventResult.ignored;
            }

            return callback() ? KeyEventResult.handled : KeyEventResult.ignored;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final callback = widget.onNavigateDown;

            if (callback == null) {
              return KeyEventResult.ignored;
            }

            return callback() ? KeyEventResult.handled : KeyEventResult.ignored;
          }

          return KeyEventResult.ignored;
        },
        onNavigateLeft: index == 0 && widget.allowLeftEdgeExit
            ? null
            : () {
                _focusAdjacent(index, -1);
              },
        onNavigateRight: index == widget.values.length - 1
            ? (widget.trapRightEdge ? () {} : null)
            : () {
                _focusAdjacent(index, 1);
              },
        onFocusChange: (focused) {
          _handleFocusChanged(focused, value);
        },
        child: Semantics(
          button: true,
          selected: selected,
          child: AnimatedBuilder(
            animation: node,
            builder: (context, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                constraints: BoxConstraints(
                  minWidth: widget.minimumSegmentWidth,
                ),
                height: widget.height - 4,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? foreground.withValues(
                          alpha: node.hasFocus ? 0.18 : 0.13,
                        )
                      : hovered
                      ? foreground.withValues(alpha: 0.07)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: node.hasFocus
                        ? foreground.withValues(alpha: 0.92)
                        : selected
                        ? foreground.withValues(alpha: 0.18)
                        : Colors.transparent,
                    width: node.hasFocus ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[leading, const SizedBox(width: 8)],
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        style:
                            theme.textTheme.titleSmall?.copyWith(
                              color: foreground.withValues(
                                alpha: selected || node.hasFocus || hovered
                                    ? 1
                                    : 0.64,
                              ),
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ) ??
                            const TextStyle(),
                        child: Text(
                          widget.labelBuilder(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
