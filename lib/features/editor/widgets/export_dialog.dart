import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/core/services/permission_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart';

// -----------------------------------------------------------------------------
// Tokens (same palette as the editor page)
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF000000);
const Color _card = Color(0xFF16161A);
const Color _track = Color(0xFF2B2B31);
const Color _selectedFill = Color(0xFF1C1C20);
const Color _doneBtn = Color(0xFF1C1C20);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9A9AA3);
const Color _purple = Color(0xFFFFFFFF);
const Color _green = Color(0xFFFFFFFF);
const Color _red = Color(0xFFFFFFFF);

final RoundedRectangleBorder _pill =
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

/// Full-screen export page. Entry point unchanged: `ExportModal.show(context)`.
class ExportModal extends StatefulWidget {
  const ExportModal({super.key});

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

class _ExportDialogEditorState {
  const _ExportDialogEditorState({
    required this.isExporting,
    required this.exportProgress,
    required this.projectName,
    required this.totalDurationMs,
  });
  final bool isExporting;
  final double exportProgress;
  final String projectName;
  final int totalDurationMs;

  @override
  bool operator ==(Object other) =>
      other is _ExportDialogEditorState &&
      other.isExporting == isExporting &&
      other.exportProgress == exportProgress &&
      other.projectName == projectName &&
      other.totalDurationMs == totalDurationMs;

  @override
  int get hashCode =>
      Object.hash(isExporting, exportProgress, projectName, totalDurationMs);
}

class _ExportModalState extends State<ExportModal> {
  late ExportResolution selectedResolution;
  late int selectedFps;
  late ExportQuality selectedQuality;
  late ExportFormat selectedFormat;
  String selectedCodec = 'h264';
  DateTime? _startedAt;

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
    context.select<EditorController, _ExportDialogEditorState>(
      (e) => _ExportDialogEditorState(
        isExporting: e.isExporting,
        exportProgress: e.exportProgress,
        projectName: e.project.projectName,
        totalDurationMs: e.project.totalDuration.inMilliseconds,
      ),
    );
    final editorCtrl = context.read<EditorController>();

    final bool isExporting = exportCtrl?.isExporting ?? editorCtrl.isExporting;
    final double progress = exportCtrl?.progress ?? editorCtrl.exportProgress;
    final ExportStatus status = exportCtrl?.status ??
        (editorCtrl.isExporting ? ExportStatus.exporting : ExportStatus.idle);

    if (isExporting) {
      _startedAt ??= DateTime.now();
    } else {
      _startedAt = null;
    }

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
    return SizedBox(
      height: 56,
      child: Row(
        children: <Widget>[
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: isExporting ? Colors.white24 : _text, size: 26),
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
              style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: <Widget>[
        _summary(editorCtrl),
        const SizedBox(height: 22),
        _label('Resolution'),
        _Segmented<ExportResolution>(
          values: ExportResolution.values,
          selected: selectedResolution,
          title: (r) => r.label,
          subtitle: (r) => '${r.width}×${r.height}',
          onChanged: (v) => setState(() => selectedResolution = v),
        ),
        const SizedBox(height: 22),
        _label('Frame rate'),
        _Segmented<int>(
          values: const <int>[24, 25, 30, 50, 60],
          selected: selectedFps,
          title: (f) => '$f',
          subtitle: (_) => 'fps',
          onChanged: (v) => setState(() => selectedFps = v),
        ),
        const SizedBox(height: 22),
        _label('Quality'),
        for (final q in ExportQuality.values)
          _QualityTile(
            title: q.label.split(' ')[0],
            subtitle: '${q.bitrateMbps.toInt()} Mbps',
            selected: q == selectedQuality,
            onTap: () => setState(() => selectedQuality = q),
          ),
        const SizedBox(height: 22),
        _label('Format'),
        _Segmented<ExportFormat>(
          values: ExportFormat.values,
          selected: selectedFormat,
          title: (f) => f.name.toUpperCase(),
          onChanged: (v) => setState(() => selectedFormat = v),
        ),
        const SizedBox(height: 22),
        _label('Codec'),
        _Segmented<String>(
          values: const <String>['h264', 'hevc'],
          selected: selectedCodec,
          title: (c) => c == 'h264' ? 'H.264' : 'HEVC',
          subtitle: (c) => c == 'h264' ? 'Most compatible' : 'Smaller files',
          onChanged: (v) => setState(() => selectedCodec = v),
        ),
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
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: <Widget>[
          Container(
            width: 96,
            height: 54,
            decoration:
                BoxDecoration(color: _track, borderRadius: BorderRadius.circular(10)),
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
                      color: _text, fontSize: 14, fontWeight: FontWeight.w700),
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
                  style: const TextStyle(color: _purple, fontSize: 12),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _purple,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: _pill,
          ),
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          label: const Text('Export',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          onPressed: () async {
            final hasPerm = await PermissionService.instance.requestMediaPermissions();
            if (!mounted) return;
            if (!hasPerm) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Storage permission is required to export videos.'),
                ),
              );
              return;
            }
            final newSettings = ExportSettings(
              resolution: selectedResolution,
              fps: selectedFps,
              quality: selectedQuality,
              format: selectedFormat,
              codec: selectedCodec,
            );
            editorCtrl.updateExportSettings(newSettings);
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

  Widget _step(String label, int state) {
    // 0 = pending, 1 = active, 2 = done
    return Expanded(
      child: Column(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state == 2 ? Colors.white : Colors.transparent,
              border: Border.all(
                  color: state == 0 ? _track : Colors.white, width: state == 1 ? 2 : 1.5),
            ),
            child: state == 2
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.black)
                : state == 1
                    ? const Center(
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : null,
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: state == 0 ? _muted : _text,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _progressView(ExportController? exportCtrl, double progress) {
    final String stage = (exportCtrl?.stage.isNotEmpty ?? false)
        ? exportCtrl!.stage
        : 'Rendering video…';
    final int pct = (progress * 100).round();
    final Duration elapsed = DateTime.now().difference(_startedAt ?? DateTime.now());
    String eta = 'Estimating…';
    if (progress > 0.03) {
      final int rem = (elapsed.inSeconds * (1 - progress) / progress).round();
      eta = rem >= 60 ? '${rem ~/ 60}m ${rem % 60}s left' : '${rem}s left';
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (_, double v, __) => SizedBox(
                width: 240,
                height: 240,
                child: CustomPaint(
                  painter: _RingPainter(v),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Text('$pct',
                                style: const TextStyle(
                                    color: _text,
                                    fontSize: 64,
                                    fontWeight: FontWeight.w300,
                                    fontFeatures: <FontFeature>[
                                      FontFeature.tabularFigures()
                                    ])),
                            const Text('%',
                                style: TextStyle(
                                    color: _muted, fontSize: 22, fontWeight: FontWeight.w400)),
                          ],
                        ),
                        Text(eta, style: const TextStyle(color: _muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(stage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _text, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '${selectedResolution.label}  ·  $selectedFps fps  ·  ${selectedCodec == 'h264' ? 'H.264' : 'HEVC'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 28),
          Row(
            children: <Widget>[
              _step('Prepare', progress > 0.05 ? 2 : 1),
              _step('Render', progress >= 0.95 ? 2 : (progress > 0.05 ? 1 : 0)),
              _step('Finalize', progress >= 0.95 ? 1 : 0),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Keep the app open until the export finishes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _text,
              side: const BorderSide(color: _track),
              minimumSize: const Size.fromHeight(50),
              shape: _pill,
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

  Widget _statusIcon(IconData icon, Color color, Color bg) => Center(
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, size: 44, color: color),
        ),
      );

  Widget _doneView(ExportController? exportCtrl) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _statusIcon(Icons.check_rounded, _green, _doneBtn),
          const SizedBox(height: 18),
          const Text('Export complete',
              textAlign: TextAlign.center,
              style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Saved to ${exportCtrl?.outputPath ?? "Gallery"}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.black,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: _pill,
            ),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Share video', style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Share option ready')),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _text,
              side: const BorderSide(color: _track),
              minimumSize: const Size.fromHeight(52),
              shape: _pill,
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
          _statusIcon(Icons.priority_high_rounded, _red, _doneBtn),
          const SizedBox(height: 18),
          const Text('Export failed',
              textAlign: TextAlign.center,
              style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            exportCtrl?.errorMessage ?? 'An error occurred during video rendering.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.black,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: _pill,
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
// Option widgets
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: <Widget>[
          for (final v in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: subtitle == null ? 42 : 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == selected ? _purple : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(title(v),
                          style: TextStyle(
                              color: v == selected ? Colors.black : _text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle!(v),
                            style: TextStyle(
                                color: v == selected ? Colors.black54 : _muted,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? _selectedFill : _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _purple : Colors.transparent, width: 2),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? _purple : _muted,
            ),
            const SizedBox(width: 12),
            Text(title,
                style: const TextStyle(
                    color: _text, fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2 - 18;
    final Rect rect = Rect.fromCircle(center: c, radius: r);

    // tick marks
    for (int i = 0; i < 60; i++) {
      final double a = -math.pi / 2 + i / 60 * 2 * math.pi;
      final bool on = i / 60 < value;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r + 10),
        c + Offset(math.cos(a), math.sin(a)) * (r + (i % 5 == 0 ? 18 : 14)),
        Paint()
          ..color = on ? Colors.white : _track
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = _track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}