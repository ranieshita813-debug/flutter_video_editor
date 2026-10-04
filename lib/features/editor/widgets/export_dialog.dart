import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

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

  @override
  void initState() {
    super.initState();
    final settings = context.read<EditorController>().exportSettings;
    selectedResolution = settings.resolution;
    selectedFps = settings.fps;
    selectedQuality = settings.quality;
    selectedFormat = settings.format;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Format', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
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
          if (controller.isExporting) ...<Widget>[
            LinearProgressIndicator(
              value: controller.exportProgress,
              backgroundColor: const Color(0xFF1F2937),
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Rendering Video... ${(controller.exportProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ] else ...<Widget>[
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
                  final newSettings = ExportSettings(
                    resolution: selectedResolution,
                    fps: selectedFps,
                    quality: selectedQuality,
                    format: selectedFormat,
                  );
                  controller.updateExportSettings(newSettings);
                  controller.startExport(onComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Export Complete! Video saved in ${selectedFormat.name.toUpperCase()} format (${selectedResolution.label}).',
                        ),
                        backgroundColor: const Color(0xFF22C55E),
                      ),
                    );
                    Navigator.of(context).pop();
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
