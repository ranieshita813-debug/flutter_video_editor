import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class OverlayLayer extends StatefulWidget {
  const OverlayLayer({super.key, required this.editor});
  final EditorController editor;

  @override
  State<OverlayLayer> createState() => _OverlayLayerState();
}

class _OverlayLayerState extends State<OverlayLayer> {
  EditorController get editor => widget.editor;

  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  Offset _basePosition = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final List<TimelineClip> activeClips = editor.clips.where((c) {
      return c.isVisible &&
          editor.playhead >= c.start &&
          editor.playhead <= c.end;
    }).toList();

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final double h = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Drawing strokes
              if (editor.activeDrawingStrokes.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DrawingPainter(strokes: editor.activeDrawingStrokes),
                  ),
                ),

              // Active clips overlays
              for (final clip in activeClips)
                _buildClipOverlay(clip, w, h),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClipOverlay(TimelineClip clip, double canvasW, double canvasH) {
    final bool isSelected = editor.selectedClipId == clip.id;

    // Direct manipulation coordinates normalized (0..1)
    double normX = clip.positionX;
    double normY = clip.positionY;
    double scale = clip.scale;
    double rotation = clip.rotation;

    // Tracking box interpolation if active
    if (clip.trackingData.isEnabled) {
      final Rect trackingRect = clip.trackingData.rect;
      normX = trackingRect.center.dx - 0.5;
      normY = trackingRect.center.dy - 0.5;
    }

    final double px = (normX + 0.5) * canvasW;
    final double py = (normY + 0.5) * canvasH;

    Widget content;
    switch (clip.clipType) {
      case ClipType.text:
      case ClipType.caption:
        content = Text(
          clip.label,
          style: TextStyle(
            color: EditorTokens.text,
            fontSize: 20 * scale,
            fontFamily: clip.fontFamily,
            fontWeight: FontWeight.bold,
          ),
        );

      case ClipType.sticker:
      case ClipType.element:
        content = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: EditorTokens.elevated.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EditorTokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                clip.clipType == ClipType.sticker
                    ? Icons.emoji_emotions_outlined
                    : Icons.shape_line_outlined,
                color: EditorTokens.text,
                size: 24 * scale,
              ),
              const SizedBox(width: 4),
              Text(
                clip.label,
                style: TextStyle(
                  color: EditorTokens.text,
                  fontSize: 12 * scale,
                ),
              ),
            ],
          ),
        );

      case ClipType.drawing:
        content = CustomPaint(
          size: Size(100 * scale, 100 * scale),
          painter: _DrawingPainter(strokes: clip.strokes),
        );

      default:
        content = const SizedBox.shrink();
    }

    if (content is SizedBox && clip.clipType != ClipType.text && clip.clipType != ClipType.sticker && clip.clipType != ClipType.element && clip.clipType != ClipType.drawing && clip.clipType != ClipType.caption) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: px - 80,
      top: py - 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          editor.selectClip(clip.id);
        },
        onScaleStart: (details) {
          editor.selectClip(clip.id);
          editor.beginGesture();
          _baseScale = clip.scale;
          _baseRotation = clip.rotation;
          _basePosition = Offset(clip.positionX, clip.positionY);
        },
        onScaleUpdate: (details) {
          if (!isSelected) return;
          final double deltaNormX = details.focalPointDelta.dx / canvasW;
          final double deltaNormY = details.focalPointDelta.dy / canvasH;

          editor.updateTranslation(
            positionX: _basePosition.dx + deltaNormX,
            positionY: _basePosition.dy + deltaNormY,
            scale: (_baseScale * details.scale).clamp(0.2, 5.0),
            rotation: _baseRotation + details.rotation,
          );
          _basePosition = Offset(_basePosition.dx + deltaNormX, _basePosition.dy + deltaNormY);
        },
        onScaleEnd: (_) {
          editor.commitGesture();
        },
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(rotation)
            ..scale(scale, scale, 1.0),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: isSelected
                ? BoxDecoration(
                    border: Border.all(color: EditorTokens.text, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                content,
                if (isSelected) ...<Widget>[
                  // Delete handle
                  Positioned(
                    top: -12,
                    left: -12,
                    child: GestureDetector(
                      onTap: () {
                        editor.deleteSelectedClip();
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: EditorTokens.text,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 14, color: EditorTokens.bg),
                      ),
                    ),
                  ),
                  // Duplicate handle
                  Positioned(
                    top: -12,
                    right: -12,
                    child: GestureDetector(
                      onTap: () {
                        editor.duplicateSelectedClip();
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: EditorTokens.text,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.copy_rounded, size: 12, color: EditorTokens.bg),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  _DrawingPainter({required this.strokes});
  final List<DrawingStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = s.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return oldDelegate.strokes.length != strokes.length;
  }
}
