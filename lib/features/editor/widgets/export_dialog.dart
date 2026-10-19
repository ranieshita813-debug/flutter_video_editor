import 'package:phosphor_icons/phosphor_icons.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/core/widgets/loading_wave.dart';
import 'package:flutter_video_editor/core/services/permission_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart';

// -----------------------------------------------------------------------------
// Dark theme tokens (CapCut style)
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF0B0B0F);
const Color _card = Color(0xFF1A1A20);
const Color _card2 = Color(0xFF24242C);
const Color _track = Color(0xFF3A3A44);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF8E8E99);
const Color _accent = Color(0xFF25F4EE);
const Color _onAccent = Color(0xFF05201F);
const Color _green = Color(0xFF4ADE80);
const Color _red = Color(0xFFFF5C5C);

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
    final editorCtrl = context.read<EditorController>();

    final bool isExporting = exportCtrl?.isExporting ??
        context.select<EditorController, bool>((e) => e.isExporting);
    final double progress = exportCtrl?.progress ??
        context.select<EditorController, double>((e) => e.exportProgress);
    final ExportStatus status = exportCtrl?.status ??
        (isExporting ? ExportStatus.exporting : ExportStatus.idle);

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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _bg,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _bg,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: _bg,
      ),
      child: PopScope(
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
            icon: Icon(PhosphorIconsRegular.x,
                color: isExporting ? Colors.white24 : _text, size: 24),
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
              style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        _preview(editorCtrl),
        const SizedBox(height: 24),
        _sectionHeader('Resolution', '${selectedResolution.width}×${selectedResolution.height}'),
        _StepSlider<ExportResolution>(
          values: ExportResolution.values,
          selected: selectedResolution,
          label: (r) => '${math.min(r.width, r.height)}p',
          onChanged: (v) => setState(() => selectedResolution = v),
        ),
        const SizedBox(height: 18),
        _sectionHeader('Frame rate', '$selectedFps fps'),
        _StepSlider<int>(
          values: const <int>[24, 25, 30, 50, 60],
          selected: selectedFps,
          label: (f) => '$f',
          onChanged: (v) => setState(() => selectedFps = v),
        ),
        const SizedBox(height: 18),
        _sectionHeader('Bitrate', null),
        Row(
          children: <Widget>[
            for (int i = 0; i < ExportQuality.values.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _QualityCard(
                  title: ExportQuality.values[i].label.split(' ')[0],
                  subtitle: '${ExportQuality.values[i].bitrateMbps.toInt()} Mbps',
                  selected: ExportQuality.values[i] == selectedQuality,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => selectedQuality = ExportQuality.values[i]);
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        _sectionHeader('Format', null),
        _ChipRow<ExportFormat>(
          values: ExportFormat.values,
          selected: selectedFormat,
          title: (f) => f.name.toUpperCase(),
          onChanged: (v) => setState(() => selectedFormat = v),
        ),
        const SizedBox(height: 18),
        _sectionHeader('Codec', null),
        _ChipRow<String>(
          values: const <String>['h264', 'hevc'],
          selected: selectedCodec,
          title: (c) => c == 'h264' ? 'H.264' : 'HEVC',
          subtitle: (c) => c == 'h264' ? 'Most compatible' : 'Smaller files',
          onChanged: (v) => setState(() => selectedCodec = v),
        ),
      ],
    );
  }

  Widget _preview(EditorController editorCtrl) {
    final double seconds = editorCtrl.project.totalDuration.inMilliseconds / 1000.0;
    final double mb = selectedQuality.bitrateMbps * seconds / 8;
    final int m = seconds ~/ 60;
    final int s = seconds.round() % 60;
    final double ratio = (selectedResolution.width / selectedResolution.height)
        .clamp(0.5, 2.0)
        .toDouble();

    return Column(
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: AspectRatio(
              aspectRatio: ratio,
              child: Container(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _card2),
                ),
                child: Stack(
                  children: <Widget>[
                    const Center(
                      child: Icon(Icons.movie_creation_outlined, color: _muted, size: 40),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$m:${s.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: _text, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          editorCtrl.project.projectName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Estimated size ≈ ${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _sectionHeader(String t, String? trailing) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: <Widget>[
            Text(t,
                style: const TextStyle(
                    color: _text, fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (trailing != null)
              Text(trailing, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      );

  Widget _bottomBar(ExportController? exportCtrl, EditorController editorCtrl) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _card2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: _onAccent,
            elevation: 0,
            shape: _pill,
          ),
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          label: const Text('Export',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
              color: state == 2 ? _accent : Colors.transparent,
              border: Border.all(
                  color: state == 0 ? _track : _accent, width: state == 1 ? 2 : 1.5),
            ),
            child: state == 2
                ? const Icon(PhosphorIconsRegular.check, size: 16, color: _onAccent)
                : state == 1
                    ? const Center(
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
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
          TextShimmerWave(
            stage,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            baseColor: _muted,
            waveColor: _text,
          ),
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
            icon: const Icon(PhosphorIconsRegular.x, size: 18),
            label: const Text('Cancel export'),
            onPressed: () => exportCtrl?.cancelExport(),
          ),
        ],
      ),
    );
  }

  // ---- Done / Failed ---------------------------------------------------------

  Widget _statusIcon(IconData icon, Color color) => Center(
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          ),
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
          _statusIcon(PhosphorIconsRegular.check, _green),
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
              backgroundColor: _accent,
              foregroundColor: _onAccent,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: _pill,
            ),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Share video', style: TextStyle(fontWeight: FontWeight.w800)),
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
          _statusIcon(Icons.priority_high_rounded, _red),
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
              backgroundColor: _accent,
              foregroundColor: _onAccent,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: _pill,
            ),
            onPressed: () => exportCtrl?.resetStatus(),
            child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Option widgets
// -----------------------------------------------------------------------------

/// CapCut-style discrete slider: tap or drag, thumb snaps to labelled stops.
class _StepSlider<T> extends StatelessWidget {
  const _StepSlider({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final int n = values.length;
    final int sel = math.max(0, values.indexOf(selected));
    final int denom = math.max(1, n - 1);

    return LayoutBuilder(builder: (BuildContext ctx, BoxConstraints c) {
      const double pad = 16;
      final double w = c.maxWidth - pad * 2;

      void pick(double dx) {
        final int i = ((dx - pad) / w * denom).round().clamp(0, n - 1).toInt();
        if (i != sel) {
          HapticFeedback.selectionClick();
          onChanged(values[i]);
        }
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => pick(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
        child: SizedBox(
          height: 66,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: pad,
                right: pad,
                top: 17,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                      color: _track, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                left: pad,
                top: 17,
                width: w * sel / denom,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                      color: _accent, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              for (int i = 0; i < n; i++)
                Positioned(
                  left: pad + w * i / denom - 3,
                  top: 16,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= sel ? _accent : _track,
                    ),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                left: pad + w * sel / denom - 12,
                top: 7,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _accent, width: 3),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ),
              for (int i = 0; i < n; i++)
                Positioned(
                  left: pad + w * i / denom - 28,
                  width: 56,
                  top: 40,
                  child: Text(
                    label(values[i]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: i == sel ? _text : _muted,
                      fontSize: 12,
                      fontWeight: i == sel ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 64,
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.10) : _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _accent : Colors.transparent, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(title,
                style: TextStyle(
                    color: selected ? _accent : _text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
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
    return Row(
      children: <Widget>[
        for (int i = 0; i < values.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(values[i]);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: subtitle == null ? 44 : 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: values[i] == selected ? _accent.withValues(alpha: 0.10) : _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: values[i] == selected ? _accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(title(values[i]),
                        style: TextStyle(
                            color: values[i] == selected ? _accent : _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!(values[i]),
                          style: const TextStyle(color: _muted, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
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

    for (int i = 0; i < 60; i++) {
      final double a = -math.pi / 2 + i / 60 * 2 * math.pi;
      final bool on = i / 60 < value;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r + 10),
        c + Offset(math.cos(a), math.sin(a)) * (r + (i % 5 == 0 ? 18 : 14)),
        Paint()
          ..color = on ? _accent : _track
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
          ..color = _card2);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = _accent,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}