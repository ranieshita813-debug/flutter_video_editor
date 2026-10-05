import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart' as model_export;

// -----------------------------------------------------------------------------
// Tokens (same palette as the editor page)
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF000000);
const Color _surface = Color(0xFF0E0F13);
const Color _elevated = Color(0xFF1A1C22);
const Color _border = Color(0xFF26282F);
const Color _text = Color(0xFFF2F3F7);
const Color _muted = Color(0xFF8A8F9C);
const Color _violet = Color(0xFF7C5CFF);
const Color _cyan = Color(0xFF22D3EE);
const Color _green = Color(0xFF22C55E);
const Color _red = Color(0xFFEF4444);

const RoundedRectangleBorder _square =
    RoundedRectangleBorder(borderRadius: BorderRadius.zero);

/// Full-screen export page. Every surface is square (no rounded corners).
class ExportModal extends StatefulWidget {
  const ExportModal({super.key});

  /// Same entry point as before: `ExportModal.show(context)`.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const ExportModal(),
      ),
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
      final settings = context.read<ExportController>().exportSettings;
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
    final ExportStatus status = exportCtrl?.status ??
        (editorCtrl.isExporting ? ExportStatus.exporting : ExportStatus.idle);

    final bool showSettings =
        status != ExportStatus.done && status != ExportStatus.failed && !isExporting;

    Widget body;
    if (status == ExportStatus.done) {
      body = _doneView(exportCtrl);
    } else if (status == ExportStatus.failed) {
      body = _failedView(exportCtrl);
    } else if (isExporting) {
      body = _progressView(exportCtrl, progress);
    } else {
      body = _settingsView(editorCtrl);
    }

    return PopScope(
      canPop: !isExporting,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _topBar(exportCtrl, isExporting),
              Expanded(child: body),
              if (showSettings) _bottomBar(exportCtrl, editorCtrl),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Top bar ---------------------------------------------------------------

  Widget _topBar(ExportController? exportCtrl, bool isExporting) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _text),
            tooltip: 'Close',
            onPressed: isExporting
                ? null
                : () {
                    exportCtrl?.resetStatus();
                    Navigator.of(context).pop();
                  },
          ),
          const Expanded(
            child: Text(
              'Export',
              textAlign: TextAlign.center,
              style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ---- Settings --------------------------------------------------------------

  Widget _settingsView(EditorController editorCtrl) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _summary(editorCtrl),
        const SizedBox(height: 20),
        _label('Resolution'),
        _Segmented<ExportResolution>(
          values: ExportResolution.values,
          selected: selectedResolution,
          title: (r) => r.label,
          subtitle: (r) => '${r.width}×${r.height}',
          onChanged: (v) => setState(() => selectedResolution = v),
        ),
        const SizedBox(height: 20),
        _label('Frame rate'),
        _Segmented<int>(
          values: const <int>[24, 30, 60],
          selected: selectedFps,
          title: (f) => '$f',
          subtitle: (_) => 'fps',
          onChanged: (v) => setState(() => selectedFps = v),
        ),
        const SizedBox(height: 20),
        _label('Quality'),
        for (final q in ExportQuality.values)
          _QualityTile(
            title: q.label.split(' ')[0],
            subtitle: '${q.bitrateMbps.toInt()} Mbps',
            selected: q == selectedQuality,
            onTap: () => setState(() => selectedQuality = q),
          ),
        const SizedBox(height: 20),
        _label('Format'),
        _Segmented<ExportFormat>(
          values: ExportFormat.values,
          selected: selectedFormat,
          title: (f) => f.name.toUpperCase(),
          onChanged: (v) => setState(() => selectedFormat = v),
        ),
        const SizedBox(height: 20),
        _label('Codec'),
        _Segmented<String>(
          values: const <String>['h264', 'hevc'],
          selected: selectedCodec,
          title: (c) => c == 'h264' ? 'H.264' : 'HEVC',
          subtitle: (c) => c == 'h264' ? 'Most compatible' : 'Smaller files',
          onChanged: (v) => setState(() => selectedCodec = v),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _summary(EditorController editorCtrl) {
    final double seconds = editorCtrl.project.totalDuration.inMilliseconds / 1000.0;
    final double mb = selectedQuality.bitrateMbps * seconds / 8;
    final int m = seconds ~/ 60;
    final int s = seconds.round() % 60;

    return Container(
      padding: const EdgeInsets.all(12),
      color: _surface,
      child: Row(
        children: <Widget>[
          Container(
            width: 96,
            height: 54,
            color: _elevated,
            child: const Icon(Icons.movie_creation_outlined, color: _muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  editorCtrl.project.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _text, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '$m:${s.toString().padLeft(2, '0')}  ·  '
                  '${selectedResolution.label}  ·  $selectedFps fps',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'Estimated size ≈ ${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB',
                  style: const TextStyle(color: _cyan, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _bottomBar(ExportController? exportCtrl, EditorController editorCtrl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _violet,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: _square,
          ),
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          label: const Text('Export',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
    );
  }

  // ---- Progress --------------------------------------------------------------

  Widget _progressView(ExportController? exportCtrl, double progress) {
    final String stage = (exportCtrl?.stage.isNotEmpty ?? false)
        ? exportCtrl!.stage
        : 'Rendering video…';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _text,
              fontSize: 56,
              fontWeight: FontWeight.w300,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(stage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 14)),
          const SizedBox(height: 28),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: _elevated,
            color: _violet,
            borderRadius: BorderRadius.zero,
          ),
          const SizedBox(height: 16),
          const Text(
            'Keep the app open until the export finishes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 40),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _red,
              side: const BorderSide(color: _red),
              minimumSize: const Size.fromHeight(48),
              shape: _square,
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel export'),
            onPressed: () => exportCtrl?.cancelExport(),
          ),
        ],
      ),
    );
  }

  // ---- Done / Failed ---------------------------------------------------------

  Widget _doneView(ExportController? exportCtrl) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Icon(Icons.check_circle_outline_rounded, size: 64, color: _green),
          const SizedBox(height: 16),
          const Text('Export complete',
              textAlign: TextAlign.center,
              style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Saved to ${exportCtrl?.outputPath ?? "Gallery"}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _violet,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(50),
              shape: _square,
            ),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Share video'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Share option ready')),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _text,
              side: const BorderSide(color: _border),
              minimumSize: const Size.fromHeight(50),
              shape: _square,
            ),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Save to gallery'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video saved to device gallery')),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              exportCtrl?.resetStatus();
              Navigator.of(context).pop();
            },
            child: const Text('Done', style: TextStyle(color: _muted)),
          ),
        ],
      ),
    );
  }

  Widget _failedView(ExportController? exportCtrl) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, size: 64, color: _red),
          const SizedBox(height: 16),
          const Text('Export failed',
              textAlign: TextAlign.center,
              style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            exportCtrl?.errorMessage ?? 'An error occurred during video rendering.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _violet,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(50),
              shape: _square,
            ),
            onPressed: () => exportCtrl?.resetStatus(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Square option widgets
// -----------------------------------------------------------------------------

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.title,
    required this.onChanged,
    this.subtitle,
  });

  final List<T> values;
  final T selected;
  final String Function(T) title;
  final String Function(T)? subtitle;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _border)),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < values.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(values[i]),
                child: Container(
                  height: subtitle == null ? 44 : 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: values[i] == selected ? _violet : _surface,
                    border: i == 0
                        ? null
                        : const Border(left: BorderSide(color: _border)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(title(values[i]),
                          style: const TextStyle(
                              color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
                      if (subtitle != null)
                        Text(subtitle!(values[i]),
                            style: TextStyle(
                                color: values[i] == selected ? Colors.white70 : _muted,
                                fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: selected ? _violet : _border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? _violet : _muted,
            ),
            const SizedBox(width: 12),
            Text(title,
                style: const TextStyle(
                    color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}