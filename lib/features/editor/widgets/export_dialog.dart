import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart' as model_export;

class ExportModal extends StatefulWidget {
  const ExportModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ExportModal(),
    );
  }

  @override
  State<ExportModal> createState() => _ExportModalState();
}

class _ExportModalState extends State<ExportModal> {
  late ExportResolution selectedResolution;
  late int selectedFps;
  late ExportQuality selectedQuality;
  late ExportFormat selectedFormat;
  String selectedCodec = 'h264';

  @override
  void initState() {
    super.initState();
    try {
      final exportCtrl = context.read<ExportController>();
      final settings = exportCtrl.exportSettings;
      selectedResolution = settings.resolution;
      selectedFps = settings.fps;
      selectedQuality = settings.quality;
      selectedFormat = settings.format;
      selectedCodec = settings.codec;
    } catch (_) {
      final settings = context.read<EditorController>().exportSettings;
      selectedResolution = settings.resolution;
      selectedFps = settings.fps;
      selectedQuality = settings.quality;
      selectedFormat = settings.format;
      selectedCodec = 'h264';
    }
  }

  @override
  Widget build(BuildContext context) {
    final exportCtrl = context.watch<ExportController?>();
    final editorCtrl = context.watch<EditorController>();

    final bool isExporting = exportCtrl?.isExporting ?? editorCtrl.isExporting;
    final double progress = exportCtrl?.progress ?? editorCtrl.exportProgress;
    final ExportStatus status = exportCtrl?.status ?? (editorCtrl.isExporting ? ExportStatus.exporting : ExportStatus.idle);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Fast Export & Render',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: isExporting
                    ? null
                    : () {
                        exportCtrl?.resetStatus();
                        Navigator.of(context).pop();
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (status == ExportStatus.done) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF166534).withAlpha(76),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E)),
                      SizedBox(width: 8),
                      Text(
                        'Export Complete!',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Saved to: ${exportCtrl?.outputPath ?? "Gallery"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Video saved to device gallery!')),
                            );
                          },
                          icon: const Icon(Icons.save_alt_rounded, size: 18),
                          label: const Text('Save to Gallery'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Share option ready!')),
                            );
                          },
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text('Share Video'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (status == ExportStatus.failed) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF991B1B).withAlpha(76),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444)),
                      SizedBox(width: 8),
                      Text(
                        'Export Failed',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    exportCtrl?.errorMessage ?? 'An error occurred during video rendering.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => exportCtrl?.resetStatus(),
                    child: const Text('Try Again', style: TextStyle(color: Color(0xFF8B5CF6))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (isExporting) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        (exportCtrl?.stage.isNotEmpty ?? false) ? exportCtrl!.stage : 'Rendering Video...',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFF374151),
                    color: const Color(0xFF8B5CF6),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel Export'),
                      onPressed: () => exportCtrl?.cancelExport(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...<Widget>[
            const Text('Format & Codec', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: SegmentedButton<ExportFormat>(
                    segments: ExportFormat.values.map((f) {
                      return ButtonSegment<ExportFormat>(
                        value: f,
                        label: Text(f.name.toUpperCase()),
                      );
                    }).toList(),
                    selected: <ExportFormat>{selectedFormat},
                    onSelectionChanged: (Set<ExportFormat> newSelection) {
                      setState(() {
                        selectedFormat = newSelection.first;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(value: 'h264', label: Text('H.264')),
                      ButtonSegment<String>(value: 'hevc', label: Text('HEVC')),
                    ],
                    selected: <String>{selectedCodec},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        selectedCodec = newSelection.first;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Resolution', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<ExportResolution>(
              segments: ExportResolution.values.map((r) {
                return ButtonSegment<ExportResolution>(
                  value: r,
                  label: Text('${r.label} (${r.width}x${r.height})'),
                );
              }).toList(),
              selected: <ExportResolution>{selectedResolution},
              onSelectionChanged: (Set<ExportResolution> newSelection) {
                setState(() {
                  selectedResolution = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Frame Rate (FPS)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 24, label: Text('24 fps')),
                ButtonSegment<int>(value: 30, label: Text('30 fps')),
                ButtonSegment<int>(value: 60, label: Text('60 fps')),
              ],
              selected: <int>{selectedFps},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  selectedFps = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Quality & Bitrate', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<ExportQuality>(
              segments: ExportQuality.values.map((q) {
                return ButtonSegment<ExportQuality>(
                  value: q,
                  label: Text('${q.label.split(' ')[0]}\n${q.bitrateMbps.toInt()} Mbps'),
                );
              }).toList(),
              selected: <ExportQuality>{selectedQuality},
              onSelectionChanged: (Set<ExportQuality> newSelection) {
                setState(() {
                  selectedQuality = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.flash_on_rounded),
                label: const Text('Export Now (Fast Engine)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: () {
                  final newSettings = model_export.ExportSettings(
                    resolution: selectedResolution,
                    fps: selectedFps,
                    quality: selectedQuality,
                    format: selectedFormat,
                    codec: selectedCodec,
                  );
                  editorCtrl.updateExportSettings(
                    ExportSettings(
                      resolution: selectedResolution,
                      fps: selectedFps,
                      quality: selectedQuality,
                      format: selectedFormat,
                    ),
                  );
                  if (exportCtrl != null) {
                    exportCtrl.startExport(editorCtrl.project, newSettings);
                  } else {
                    editorCtrl.startExport();
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
