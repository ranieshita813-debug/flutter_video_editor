import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

const Color _sheet = Color(0xFF0E0E11);
const Color _card = Color(0xFF1A1A1F);
const Color _track = Color(0xFF2B2B31);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9A9AA3);

class VectorDrawingSheet extends StatefulWidget {
  const VectorDrawingSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const VectorDrawingSheet(),
    );
  }

  @override
  State<VectorDrawingSheet> createState() => _VectorDrawingSheetState();
}

class _VectorDrawingSheetState extends State<VectorDrawingSheet> {
  List<Offset> currentPoints = <Offset>[];

  final List<Color> palette = const <Color>[
    Colors.white,
    Color(0xFFE0E0E0),
    Color(0xFF9E9E9E),
    Color(0xFF616161),
    Colors.black,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text(
                  'Vector Drawing Canvas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01, color: Colors.white70),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    controller.clearActiveDrawing();
                    setState(() {
                      currentPoints.clear();
                    });
                  },
                  tooltip: 'Clear Canvas',
                ),
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedTick01, color: Colors.white),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    controller.saveVectorDrawingAsClip();
                    Navigator.of(context).pop();
                  },
                  tooltip: 'Save Layer',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _track),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: GestureDetector(
                    onPanStart: (DragStartDetails details) {
                      setState(() {
                        currentPoints = <Offset>[details.localPosition];
                      });
                    },
                    onPanUpdate: (DragUpdateDetails details) {
                      setState(() {
                        currentPoints.add(details.localPosition);
                      });
                    },
                    onPanEnd: (DragEndDetails details) {
                      if (currentPoints.isNotEmpty) {
                        controller.addStrokeToActiveDrawing(
                          DrawingStroke(
                            id: 'stroke_${DateTime.now().millisecondsSinceEpoch}',
                            points: List<Offset>.from(currentPoints),
                            color: controller.drawingColor,
                            strokeWidth: controller.strokeWidth,
                          ),
                        );
                        setState(() {
                          currentPoints.clear();
                        });
                      }
                    },
                    child: CustomPaint(
                      painter: _DrawingCanvasPainter(
                        strokes: controller.activeDrawingStrokes,
                        currentPoints: currentPoints,
                        currentColor: controller.drawingColor,
                        currentWidth: controller.strokeWidth,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text('Width:', style: TextStyle(color: _muted, fontSize: 13)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: _track,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: controller.strokeWidth,
                      min: 1.0,
                      max: 20.0,
                      onChanged: (val) => controller.setStrokeWidth(val),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: palette.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final color = palette[index];
                  final isSelected = controller.drawingColor == color;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.setDrawingColor(color);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : _track,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingCanvasPainter extends CustomPainter {
  _DrawingCanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
  });

  final List<DrawingStroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length > 1) {
        for (int i = 0; i < stroke.points.length - 1; i++) {
          canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
        }
      } else if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points[0], stroke.strokeWidth / 2, paint);
      }
    }

    if (currentPoints.isNotEmpty) {
      final paint = Paint()
        ..color = currentColor
        ..strokeWidth = currentWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (currentPoints.length > 1) {
        for (int i = 0; i < currentPoints.length - 1; i++) {
          canvas.drawLine(currentPoints[i], currentPoints[i + 1], paint);
        }
      } else if (currentPoints.length == 1) {
        canvas.drawCircle(currentPoints[0], currentWidth / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
