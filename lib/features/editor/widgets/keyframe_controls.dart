import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';

const Color _barBg = Color(0xFF111111);

/// Bar shown between the preview and the timeline:
/// [prev kf] [add/remove kf] [next kf] [curve]   time
class PreviewControlsBar extends StatelessWidget {
  const PreviewControlsBar({super.key, required this.editor});
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _barBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: <Widget>[
          KeyframeControls(editor: editor),
          const Spacer(),
          ValueListenableBuilder<Duration>(
            valueListenable: editor.playheadListenable,
            builder: (_, p, __) => Text(
              '${formatTimecodeMMSS(secondsOf(p))}/${formatTimecodeMMSS(secondsOf(editor.project.totalDuration))}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Previous / add-remove / next keyframe + keyframe curve buttons.
class KeyframeControls extends StatelessWidget {
  const KeyframeControls({super.key, required this.editor});
  final EditorController editor;

  static const Duration _eps = Duration(milliseconds: 40);

  bool _hasAt(TimelineClip c, Duration rel) => c.keyframes
      .any((k) => (k.time.inMilliseconds - rel.inMilliseconds).abs() < 100);

  Widget _btn(Widget icon, String tip, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Tooltip(
        message: tip,
        child: InkResponse(
          radius: 20,
          onTap: onTap == null
              ? null
              : () {
                  tapFeedback();
                  onTap();
                },
          child: Padding(padding: const EdgeInsets.all(6), child: icon),
        ),
      ),
    );
  }

  Widget _faIcon(FaIconData icon, {bool active = false}) => FaIcon(
        icon,
        size: 18,
        color: active ? accentToken : Colors.white,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[editor, editor.playheadListenable]),
      builder: (context, _) {
        final TimelineClip? clip = editor.selectedClip;
        final Duration playhead = editor.playhead;
        final Duration rel = clip == null ? Duration.zero : playhead - clip.start;
        final bool inRange = clip != null && !rel.isNegative && rel <= clip.duration;
        final bool has = inRange && _hasAt(clip, rel);

        // Absolute keyframe times, sorted.
        final List<Duration> times = clip == null
            ? const <Duration>[]
            : (<Duration>[for (final k in clip.keyframes) clip.start + k.time]..sort());
        Duration? prev;
        Duration? next;
        for (final t in times) {
          if (t < playhead - _eps) prev = t;
          if (t > playhead + _eps && next == null) next = t;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _btn(
              _faIcon(FontAwesomeIcons.chevronLeft),
              'Previous keyframe',
              prev == null ? null : () => seekPlayhead(editor, secondsOf(prev!)),
            ),
            _btn(
              _faIcon(
                has ? FontAwesomeIcons.minus : FontAwesomeIcons.plus,
                active: has,
              ),
              has ? 'Remove keyframe' : 'Add keyframe',
              !inRange
                  ? null
                  : () {
                      final TimelineClip c = clip;
                      if (has) {
                        final kfs = c.keyframes.where((k) =>
                            (k.time.inMilliseconds - rel.inMilliseconds).abs() < 100).toList();
                        for (final k in kfs) {
                          editor.removeKeyframe(k.id);
                        }
                      } else {
                        editor.addKeyframeAtPlayhead();
                      }
                    },
            ),
            _btn(
              _faIcon(FontAwesomeIcons.chevronRight),
              'Next keyframe',
              next == null ? null : () => seekPlayhead(editor, secondsOf(next!)),
            ),
            _btn(
              _faIcon(FontAwesomeIcons.chartLine),
              'Keyframe curve',
              clip == null
                  ? null
                  : () => showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: _barBg,
                        shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(16))),
                        builder: (_) => const KeyframeSheet(),
                      ),
            ),
          ],
        );
      },
    );
  }
}