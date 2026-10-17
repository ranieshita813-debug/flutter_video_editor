import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/keyframe_controls.dart';

class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.editor});
  final EditorController editor;

  Widget _icon(IconData i, String tip, VoidCallback onTap, double s) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: 40 * s, height: 40 * s),
        icon: Icon(i, color: Colors.white, size: 22 * s),
        onPressed: () {
          tapFeedback();
          onTap();
        },
      );

  @override
  Widget build(BuildContext context) {
    final double s = scaleOf(MediaQuery.sizeOf(context));

    return Container(
      color: bgToken,
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
      child: Row(
        children: <Widget>[
          KeyframeControls(editor: editor),
          const Expanded(child: SizedBox.shrink()),
          _icon(PhosphorIconsRegular.skipBack, 'Previous frame',
              () => seekPlayhead(editor, secondsOf(editor.playhead) - 1 / fpsToken), s),
          Selector<EditorController, bool>(
            selector: (_, e) => e.isPlaying,
            builder: (_, playing, __) => Semantics(
              button: true,
              label: playing ? 'Pause' : 'Play',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  tapFeedback();
                  editor.togglePlayback();
                },
                child: Container(
                  width: 48 * s,
                  height: 48 * s,
                  margin: EdgeInsets.symmetric(horizontal: 2 * s),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                        playing ? PhosphorIconsRegular.pause : PhosphorIconsRegular.play,
                        key: ValueKey<bool>(playing),
                        color: Colors.white,
                        size: 38 * s),
                  ),
                ),
              ),
            ),
          ),
          _icon(PhosphorIconsRegular.skipForward, 'Next frame',
              () => seekPlayhead(editor, secondsOf(editor.playhead) + 1 / fpsToken), s),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _icon(PhosphorIconsRegular.arrowUUpLeft, 'Undo', editor.undo, s),
                  _icon(PhosphorIconsRegular.arrowUUpRight, 'Redo', editor.redo, s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
