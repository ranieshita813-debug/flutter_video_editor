import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

class VectorDrawingSheet extends StatefulWidget {
  const VectorDrawingSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
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
    Colors.purpleAccent,
    Colors.lightBlueAccent,
    Colors.greenAccent,
    Colors.amberAccent,
    Colors.redAccent,
    Colors.white,
    Colors.black,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Vector Drawing Canvas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () {
                      controller.clearActiveDrawing();
                      setState(() {
                        currentPoints.clear();
                      });
                    },
                    tooltip: 'Clear Canvas',
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.greenAccent),
                    onPressed: () {
                      controller.saveVectorDrawingAsClip();
                      Navigator.of(context).pop();
                    },
                    tooltip: 'Save Layer',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF374151)),
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
              const Text('Stroke Width:', style: TextStyle(color: Colors.white70)),
              Expanded(
                child: Slider(
                  value: controller.strokeWidth,
                  min: 1.0,
                  max: 20.0,
                  activeColor: controller.drawingColor,
                  onChanged: (val) => controller.setStrokeWidth(val),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: palette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final color = palette[index];
                final isSelected = controller.drawingColor == color;
                return GestureDetector(
                  onTap: () => controller.setDrawingColor(color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
