import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/audio_tools_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/camera_tracking_panel.dart';
import 'package:flutter_video_editor/features/editor/widgets/color_grading_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/text_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/vector_drawing_sheet.dart';

class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopToolbar(editor: editor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: _EditorWorkspace(editor: editor),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 280,
                      child: _InspectorPanel(editor: editor),
                    ),
                  ],
                ),
              ),
            ),
            _TimelineSection(editor: editor),
          ],
        ),
      ),
    );
  }
}

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            const Icon(Icons.movie_creation_outlined, color: Color(0xFF8B5CF6), size: 26),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  editor.project.projectName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'CapCut & Pro Studio Edition',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.undo_rounded, color: Colors.white, size: 20),
              tooltip: 'Undo',
              onPressed: editor.canUndo ? editor.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo_rounded, color: Colors.white, size: 20),
              tooltip: 'Redo',
              onPressed: editor.canRedo ? editor.redo : null,
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF8B5CF6)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.save_alt_rounded, size: 16, color: Color(0xFF8B5CF6)),
              label: const Text('Export', style: TextStyle(fontSize: 13)),
              onPressed: () => ExportModal.show(context),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: editor.togglePlayback,
              icon: Icon(
                editor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 18,
              ),
              label: Text(editor.isPlaying ? 'Pause' : 'Preview', style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorWorkspace extends StatelessWidget {
  const _EditorWorkspace({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final clip = editor.selectedClip;
    final tracking = clip?.trackingData;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF111827),
            Color(0xFF0F172A),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF1F2937),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: <Widget>[
                    // Camera feed preview simulation
                    if (editor.isCameraActive)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black87,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.camera_alt, size: 48, color: Color(0xFF8B5CF6)),
                                SizedBox(height: 8),
                                Text('Live Camera Preview Active', style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(Icons.videocam_outlined, size: 56, color: Colors.white70),
                            const SizedBox(height: 10),
                            Text(
                              clip != null ? 'Active: ${clip.label}' : 'Canvas Preview',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Playhead: ${EditorUtils.formatDuration(editor.playhead)}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),

                    // Render Vector Strokes on Preview Canvas
                    if (editor.activeDrawingStrokes.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PreviewCanvasDrawingPainter(strokes: editor.activeDrawingStrokes),
                        ),
                      ),

                    // Tracking Box Overlay
                    if (tracking != null && tracking.isEnabled)
                      Positioned(
                        left: 100,
                        top: 80,
                        width: 140,
                        height: 140,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.greenAccent, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              color: Colors.greenAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Text(
                                'Tracking: ${tracking.targetName}',
                                style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Tools Quick Action Bar
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _QuickAction(
                    icon: Icons.content_cut_rounded,
                    label: 'Split',
                    onTap: editor.splitSelectedClip,
                  ),
                  _QuickAction(
                    icon: Icons.brush_rounded,
                    label: 'Vector Draw',
                    onTap: () => VectorDrawingSheet.show(context),
                  ),
                  _QuickAction(
                    icon: Icons.title_rounded,
                    label: 'Text & Font',
                    onTap: () => TextAnimationSheet.show(context),
                  ),
                  _QuickAction(
                    icon: Icons.color_lens_rounded,
                    label: 'Color Grade',
                    onTap: () => ColorGradingSheet.show(context),
                  ),
                  _QuickAction(
                    icon: Icons.graphic_eq_rounded,
                    label: 'Audio Tools',
                    onTap: () => AudioToolsSheet.show(context),
                  ),
                  _QuickAction(
                    icon: Icons.center_focus_strong_rounded,
                    label: 'Camera & Track',
                    onTap: () => CameraTrackingPanel.show(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCanvasDrawingPainter extends CustomPainter {
  _PreviewCanvasDrawingPainter({required this.strokes});
  final List<DrawingStroke> strokes;

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
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF374151)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: const Color(0xFF8B5CF6)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final clip = editor.selectedClip;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Clip Inspector',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (clip != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 18),
                    onPressed: editor.deleteSelectedClip,
                    tooltip: 'Delete Clip',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (clip == null)
              const Text('No clip selected', style: TextStyle(color: Colors.white54))
            else ...<Widget>[
              _InspectorOption(title: 'Label', value: clip.label),
              _InspectorOption(title: 'Type', value: clip.clipType.name.toUpperCase()),
              _InspectorOption(title: 'Duration', value: EditorUtils.formatDuration(clip.duration)),
              _InspectorOption(title: 'Start-End', value: '${EditorUtils.formatDuration(clip.start)} - ${EditorUtils.formatDuration(clip.end)}'),
              _InspectorOption(title: 'Layer', value: 'Track ${clip.layerIndex + 1}'),
              if (clip.clipType == ClipType.text) ...<Widget>[
                _InspectorOption(title: 'Font', value: clip.fontFamily),
                _InspectorOption(title: 'Animation', value: clip.textAnimationStyle.name),
              ],
              if (clip.clipType == ClipType.video) ...<Widget>[
                _InspectorOption(title: 'Filter/LUT', value: clip.effect.name),
                _InspectorOption(
                  title: 'Brightness',
                  value: clip.colorGrading.brightness.toStringAsFixed(2),
                ),
              ],
              if (clip.clipType == ClipType.audio) ...<Widget>[
                _InspectorOption(title: 'Volume', value: '${(clip.volume * 100).round()}%'),
                _InspectorOption(title: 'Equalizer', value: clip.audioProperties.equalizerPreset),
              ],
            ],
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF1F2937)),
            const SizedBox(height: 6),
            const Text(
              'Quick Actions',
              style: TextStyle(
                color: Color(0xFF8B5CF6),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.subtitles, size: 16),
                label: const Text('Auto Captions', style: TextStyle(fontSize: 12)),
                onPressed: editor.generateAutoCaptions,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_a_photo, size: 16),
                label: const Text('Live Camera Feed', style: TextStyle(fontSize: 12)),
                onPressed: () => CameraTrackingPanel.show(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorOption extends StatelessWidget {
  const _InspectorOption({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1F2937))),
        color: Color(0xFF0F172A),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Multi-Layer Timeline',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Zoom: ${editor.zoom.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.zoom_out, color: Colors.white70, size: 18),
                onPressed: () => editor.setZoom(editor.zoom - 0.2),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                onPressed: () => editor.setZoom(editor.zoom + 0.2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF374151)),
              ),
              child: ListView.builder(
                itemCount: editor.project.clips.length,
                itemBuilder: (BuildContext context, int index) {
                  final clip = editor.project.clips[index];
                  final color = switch (clip.clipType) {
                    ClipType.video => const Color(0xFF8B5CF6),
                    ClipType.audio => const Color(0xFF22C55E),
                    ClipType.text => const Color(0xFF38BDF8),
                    ClipType.drawing => const Color(0xFFEC4899),
                    ClipType.image => const Color(0xFFF59E0B),
                    ClipType.sticker => const Color(0xFFF472B6),
                    ClipType.caption => const Color(0xFF10B981),
                  };

                  final isSelected = editor.selectedClipId == clip.id;

                  return GestureDetector(
                    onTap: () => editor.selectClip(clip.id),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF0F172A),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF1F2937),
                          width: isSelected ? 2.0 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              clip.isVisible ? Icons.visibility : Icons.visibility_off,
                              size: 16,
                              color: clip.isVisible ? Colors.white70 : Colors.white24,
                            ),
                            onPressed: () => editor.toggleClipVisibility(clip.id),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              clip.isLocked ? Icons.lock : Icons.lock_open,
                              size: 16,
                              color: clip.isLocked ? Colors.amberAccent : Colors.white24,
                            ),
                            onPressed: () => editor.toggleClipLock(clip.id),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: color),
                            ),
                            child: Text(
                              'Track ${clip.layerIndex + 1}',
                              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  clip.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${clip.clipType.name.toUpperCase()} • ${EditorUtils.formatDuration(clip.duration)}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 100 * editor.zoom,
                            height: 26,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              clip.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
