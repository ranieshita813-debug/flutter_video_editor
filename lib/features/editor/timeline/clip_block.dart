import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/services/thumbnail_cache.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

enum ClipKind { text, video, audio }

class ClipBlock extends StatelessWidget {
  const ClipBlock({
    super.key,
    required this.editor,
    required this.clip,
    required this.kind,
    required this.pps,
  });

  final EditorController editor;
  final TimelineClip clip;
  final ClipKind kind;
  final double pps;

  void _tap() => HapticFeedback.selectionClick();

  @override
  Widget build(BuildContext context) {
    final bool isSelected = editor.selectedClipId == clip.id ||
        editor.multiSelectedClipIds.contains(clip.id);

    final double width = math.max(
      EditorTokens.minTouchTarget,
      (clip.duration.inMilliseconds / 1000.0) * pps,
    );

    Widget body;
    switch (kind) {
      case ClipKind.text:
        final bool sticker =
            clip.clipType == ClipType.sticker || clip.clipType == ClipType.element;
        final bool drawing = clip.clipType == ClipType.drawing;
        final Color bg = drawing
            ? EditorTokens.drawTrack
            : (sticker ? EditorTokens.fxTrack : EditorTokens.textTrack);
        final IconData icon = drawing
            ? Icons.brush_rounded
            : (sticker ? Icons.emoji_emotions_rounded : Icons.title_rounded);

        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? EditorTokens.sideSelected : Border.all(color: EditorTokens.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 14, color: EditorTokens.text),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  clip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: EditorTokens.text,
                    fontSize: EditorTokens.minFontSize,
                  ),
                ),
              ),
            ],
          ),
        );

      case ClipKind.video:
        body = Container(
          decoration: BoxDecoration(
            color: EditorTokens.videoTrack,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? EditorTokens.sideSelected : Border.all(color: EditorTokens.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _VideoThumbnailStrip(clip: clip),
                Positioned(
                  right: 4,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${(clip.duration.inMilliseconds / 1000.0).toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: EditorTokens.text,
                        fontSize: EditorTokens.minFontSize - 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case ClipKind.audio:
        body = Container(
          decoration: BoxDecoration(
            color: EditorTokens.audioTrack,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? EditorTokens.sideSelected : Border.all(color: EditorTokens.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _AudioWaveformBar(clip: clip),
          ),
        );
    }

    Widget block = GestureDetector(
      onTap: () {
        _tap();
        editor.selectClip(clip.id);
      },
      onLongPress: () {
        _tap();
        editor.selectClip(clip.id, toggleMulti: true);
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: clip.isVisible ? 1.0 : 0.35,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(child: body),
            if (clip.isLocked)
              const Positioned(
                top: 4,
                right: 6,
                child: Icon(Icons.lock_rounded, size: 12, color: EditorTokens.muted),
              ),
          ],
        ),
      ),
    );

    // Selected white trim handles
    if (isSelected && !clip.isLocked) {
      block = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(child: block),
          // Left handle (trim start)
          Positioned(
            left: -6,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => editor.beginGesture(),
              onHorizontalDragUpdate: (details) {
                final double dt = details.delta.dx / pps;
                final Duration newTrimStart = clip.trimStart + Duration(milliseconds: (dt * 1000).round());
                editor.updateClipTrim(clip.id, trimStart: newTrimStart);
              },
              onHorizontalDragEnd: (_) => editor.commitGesture(),
              child: const _TrimHandle(),
            ),
          ),
          // Right handle (trim end)
          Positioned(
            right: -6,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => editor.beginGesture(),
              onHorizontalDragUpdate: (details) {
                final double dt = -details.delta.dx / pps;
                final Duration newTrimEnd = clip.trimEnd + Duration(milliseconds: (dt * 1000).round());
                editor.updateClipTrim(clip.id, trimEnd: newTrimEnd);
              },
              onHorizontalDragEnd: (_) => editor.commitGesture(),
              child: const _TrimHandle(),
            ),
          ),
        ],
      );
    }

    return SizedBox(width: width, child: block);
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      decoration: BoxDecoration(
        color: EditorTokens.text,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: SizedBox(
          width: 2,
          height: 12,
          child: ColoredBox(color: EditorTokens.bg),
        ),
      ),
    );
  }
}

class _VideoThumbnailStrip extends StatelessWidget {
  const _VideoThumbnailStrip({required this.clip});
  final TimelineClip clip;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FilmStripPainter(),
    );
  }
}

class _FilmStripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = EditorTokens.elevated);
    final double fw = size.height * 0.85;
    int i = 0;
    for (double x = 0; x < size.width; x += fw) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, fw - 1, size.height),
        Paint()..color = (i++ % 2 == 0) ? EditorTokens.border : EditorTokens.elevated,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AudioWaveformBar extends StatelessWidget {
  const _AudioWaveformBar({required this.clip});
  final TimelineClip clip;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<double>>(
      future: ThumbnailCache.instance.getWaveformPeaks(clip.sourcePath ?? clip.id),
      builder: (context, snapshot) {
        final peaks = snapshot.data ?? <double>[];
        return CustomPaint(
          painter: _WaveformPainter(peaks: peaks),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.peaks});
  final List<double> peaks;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = EditorTokens.text
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    if (peaks.isEmpty) return;

    const double gap = 4.0;
    final int count = (size.width / gap).floor();
    for (int i = 0; i < count; i++) {
      final double x = i * gap + 2;
      final double peak = peaks[i % peaks.length];
      final double h = math.max(2.0, peak * (size.height - 8));
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => oldDelegate.peaks != peaks;
}
