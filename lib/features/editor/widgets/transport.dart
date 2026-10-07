import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

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
    const List<FontFeature> tab = <FontFeature>[FontFeature.tabularFigures()];

    return Container(
      color: bgToken,
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Selector<EditorController, Duration>(
                selector: (_, e) => e.playhead,
                builder: (_, p, __) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(formatTimecode(secondsOf(p)),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFeatures: tab)),
                      Text(
                          formatTimecode(
                              math.max(secondsOf(editor.project.totalDuration), 1.0)),
                          style: const TextStyle(
                              color: mutedToken, fontSize: 9, fontFeatures: tab)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _icon(Icons.skip_previous_rounded, 'Previous frame',
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
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(playing),
                        color: Colors.white,
                        size: 38 * s),
                  ),
                ),
              ),
            ),
          ),
          _icon(Icons.skip_next_rounded, 'Next frame',
              () => seekPlayhead(editor, secondsOf(editor.playhead) + 1 / fpsToken), s),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _icon(Icons.undo_rounded, 'Undo', editor.undo, s),
                  _icon(Icons.redo_rounded, 'Redo', editor.redo, s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
