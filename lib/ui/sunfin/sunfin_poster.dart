import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/aggregated_item.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/focus/key_event_utils.dart';
import '../../util/image_fetch_priority.dart';
import '../../util/item_watch_state.dart';
import '../widgets/image_source.dart';
import 'sunfin_style.dart';

/// The reference design's corner tag on a poster: the episodes left to watch, or a check once
/// there are none (references 09-11 and 13).
class SunfinCornerBadge extends StatelessWidget {
  final int? count;

  const SunfinCornerBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final size = SunfinStyle.s(11);
    return Container(
      constraints: BoxConstraints(minWidth: SunfinStyle.s(20)),
      padding: EdgeInsets.symmetric(
        horizontal: SunfinStyle.s(5),
        vertical: SunfinStyle.s(2),
      ),
      alignment: Alignment.center,
      color: Colors.black.withValues(alpha: 0.8),
      child: count == null
          ? Icon(Icons.check, size: size * 1.2, color: Colors.white)
          : Text(
              '$count',
              style: TextStyle(
                color: Colors.white,
                fontSize: size,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }
}

/// One title in a Sunfin library grid or row (references 09-11): the artwork,
/// its corner badge and progress bar, and the title and a second line centred
/// under it. Focus scales the artwork up from its centre with a thin white
/// border and moves the captions down by as much as it grew.
///
/// It follows its own [focusNode], so moving focus rebuilds the two cards
/// involved and nothing else on the page.
class SunfinPosterCard extends StatefulWidget {
  final AggregatedItem item;
  final String? imageUrl;
  final double width;
  final double aspectRatio;
  final String title;
  final String? subtitle;

  /// Off on hub rows, which show bare posters as on home.
  final bool showCaptions;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final FocusOnKeyEventCallback? onKeyEvent;

  const SunfinPosterCard({
    super.key,
    required this.item,
    required this.imageUrl,
    required this.width,
    required this.aspectRatio,
    required this.title,
    this.subtitle,
    this.showCaptions = true,
    required this.focusNode,
    required this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.onKeyEvent,
  });

  /// The reference design grows the focused poster by about a tenth (240 to 264 px wide).
  static const focusScale = 1.1;

  /// Height under the artwork for the two caption lines.
  static final captionHeight = SunfinStyle.s(45);

  /// Height a card needs in a grid or row: the artwork, the captions, and
  /// the half of the focus growth that pushes the captions down.
  static double cellHeight(double width, double aspectRatio) {
    final height = width / aspectRatio;
    return height + height * (focusScale - 1) / 2 + captionHeight;
  }

  /// Decode width for artwork shown [width] wide, focus growth included.
  static int decodeWidth(BuildContext context, double width) =>
      ArtworkDecode.widthFor(
        width * focusScale,
        MediaQuery.devicePixelRatioOf(context),
      );

  @override
  State<SunfinPosterCard> createState() => _SunfinPosterCardState();
}

class _SunfinPosterCardState extends State<SunfinPosterCard> {
  final _selectKeys = LongPressSelectKeyHandler();
  late bool _focused = widget.focusNode.hasFocus;

  @override
  void dispose() {
    _selectKeys.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (focused != _focused) setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final longPress = widget.onLongPress;
    if (longPress != null) {
      final result = _selectKeys.handleKeyEvent(
        event,
        onTap: widget.onTap,
        onLongPress: longPress,
      );
      if (result != KeyEventResult.ignored) return result;
      if (event is KeyDownEvent && event.logicalKey.isContextMenuKey) {
        longPress();
        return KeyEventResult.handled;
      }
    } else if (isActivateKey(event)) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    return widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
  }

  Widget _placeholder() => Center(
    child: Padding(
      padding: EdgeInsets.all(SunfinStyle.s(8)),
      child: Text(
        widget.title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white70, fontSize: SunfinStyle.s(11)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final width = widget.width;
    final height = width / widget.aspectRatio;
    final grow = height * (SunfinPosterCard.focusScale - 1) / 2;
    final radius = BorderRadius.circular(SunfinStyle.s(2));
    final url = widget.imageUrl;
    final decodeWidth = SunfinPosterCard.decodeWidth(context, width);
    final unplayed = item.unplayedItemCount ?? 0;
    final container =
        item.type == 'Series' || item.type == 'Season' || item.type == 'BoxSet';
    final showCount = container && unplayed > 0;
    final showCheck = item.isPlayed && !showCount;
    final progress = ((cardProgressOf(item) ?? 0) / 100).clamp(0.0, 1.0);

    final poster = Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: radius,
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: Colors.white,
                width: SunfinStyle.focusBorderWidth,
              ),
            )
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null)
            _placeholder()
          else
            Image(
              image: ArtworkDecode.provider(
                url,
                width: decodeWidth,
                headers: artworkFetchHeaders(url, ImageFetchPriority.normal),
              ),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _placeholder(),
            ),
          if (showCount || showCheck)
            Positioned(
              top: 0,
              right: 0,
              child: SunfinCornerBadge(count: showCount ? unplayed : null),
            ),
          if (progress > 0 && progress < 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: SunfinStyle.s(3),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.6),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: const ColoredBox(color: SunfinStyle.accent),
                ),
              ),
            ),
        ],
      ),
    );

    final subtitle = widget.subtitle;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                child: AnimatedScale(
                  scale: _focused ? SunfinPosterCard.focusScale : 1,
                  duration: SunfinMotion.focus,
                  curve: SunfinMotion.curve,
                  child: poster,
                ),
              ),
              if (widget.showCaptions)
                AnimatedPadding(
                  duration: SunfinMotion.focus,
                  curve: SunfinMotion.curve,
                  padding: EdgeInsets.only(
                    top: SunfinStyle.s(7) + (_focused ? grow : 0),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: SunfinStyle.s(12.5),
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: SunfinStyle.s(11.5),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
