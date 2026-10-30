import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:server_core/server_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../plex/plex_style.dart';

/// The chapters of what is playing, as a row of thumbnails under the TV
/// controls. Down from the controls opens it: the player's next and previous
/// buttons step episodes, so chapters live here instead of behind a button
/// (user, 2026-10-30).
///
/// One focus node for the whole row; left and right move the highlight, OK
/// jumps to that chapter, and up or back leave the row.
class PlayerChapterRow extends StatefulWidget {
  final List<Map<String, dynamic>> chapters;
  final String itemId;
  final ImageApi imageApi;

  /// Where playback is, so the row opens on the chapter being watched.
  final Duration position;
  final FocusNode focusNode;
  final ValueChanged<Duration> onPick;

  /// Up or back: the row closes and focus goes back to the controls.
  final VoidCallback onLeave;

  /// Any key in the row, so the controls stay up while it is used.
  final VoidCallback onActivity;

  const PlayerChapterRow({
    super.key,
    required this.chapters,
    required this.itemId,
    required this.imageApi,
    required this.position,
    required this.focusNode,
    required this.onPick,
    required this.onLeave,
    required this.onActivity,
  });

  /// The chapter [position] falls in: the last one starting at or before it.
  static int chapterAt(List<Map<String, dynamic>> chapters, Duration position) {
    var index = 0;
    for (var i = 0; i < chapters.length; i++) {
      if (startOf(chapters[i]) <= position) index = i;
    }
    return index;
  }

  static Duration startOf(Map<String, dynamic> chapter) =>
      Duration(microseconds: (chapter['StartPositionTicks'] as int? ?? 0) ~/ 10);

  @override
  State<PlayerChapterRow> createState() => _PlayerChapterRowState();
}

class _PlayerChapterRowState extends State<PlayerChapterRow> {
  static final _cardWidth = PlexStyle.s(150);
  static final _gap = PlexStyle.s(12);
  static double get _extent => _cardWidth + _gap;

  late int _index = PlayerChapterRow.chapterAt(
    widget.chapters,
    widget.position,
  );
  late final _scroll = ScrollController(
    initialScrollOffset: math.max(0, (_index - 1) * _extent),
  );

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _scroll.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _moveTo(int index) {
    final next = index.clamp(0, widget.chapters.length - 1);
    if (next == _index) return;
    setState(() => _index = next);
    if (!_scroll.hasClients) return;
    // Keeps one card of what came before in view, as the Plex rows do.
    final target = math
        .max(0.0, (next - 1) * _extent)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    widget.onActivity();
    if (key.isLeftKey) {
      _moveTo(_index - 1);
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      _moveTo(_index + 1);
      return KeyEventResult.handled;
    }
    if (isActivateKey(event)) {
      widget.onPick(PlayerChapterRow.startOf(widget.chapters[_index]));
      return KeyEventResult.handled;
    }
    if (key.isUpKey || key.isBackKey || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) widget.onLeave();
      return KeyEventResult.handled;
    }
    // Nothing below the row, and down must not wander out of the player.
    if (key.isDownKey) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final focused = widget.focusNode.hasFocus;
    final decodeWidth = (_cardWidth * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: SizedBox(
        height: _cardWidth * 9 / 16 + PlexStyle.s(44),
        child: ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemExtent: _extent,
          itemCount: widget.chapters.length,
          itemBuilder: (context, index) {
            final chapter = widget.chapters[index];
            final name = (chapter['Name'] as String?)?.trim();
            return _ChapterCard(
              width: _cardWidth,
              title: name == null || name.isEmpty
                  ? l10n.chapterNumber(index + 1)
                  : name,
              start: PlayerChapterRow.startOf(chapter),
              imageUrl: widget.imageApi.getChapterImageUrl(
                widget.itemId,
                index: index,
                maxWidth: decodeWidth,
                tag: chapter['ImageTag'] as String?,
              ),
              highlighted: focused && index == _index,
              onTap: () => widget.onPick(PlayerChapterRow.startOf(chapter)),
            );
          },
        ),
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final double width;
  final String title;
  final Duration start;
  final String imageUrl;
  final bool highlighted;
  final VoidCallback onTap;

  const _ChapterCard({
    required this.width,
    required this.title,
    required this.start,
    required this.imageUrl,
    required this.highlighted,
    required this.onTap,
  });

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(PlexStyle.posterRadius);
    final caption = TextStyle(
      color: Colors.white.withValues(alpha: highlighted ? 1 : 0.75),
      fontSize: PlexStyle.s(11.5),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: highlighted ? 1.06 : 1,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Container(
                  width: width,
                  height: width * 9 / 16,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: highlighted ? Colors.white : Colors.transparent,
                      width: PlexStyle.focusBorderWidth,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Image.network(
                      imageUrl,
                      headers: serverImageHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: Text(_clock(start), style: caption),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: PlexStyle.s(6)),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: caption.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(_clock(start), style: caption),
            ],
          ),
        ),
      ),
    );
  }
}
