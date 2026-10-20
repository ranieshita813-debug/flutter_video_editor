import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

const Color _accent = Color(0xFF25F4EE); // CapCut cyan, same as the TTS sheet
const String _font = 'Ubuntu';

String _fmtSpeed(double v) {
  final s = v.toStringAsFixed(2);
  return '${s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
}

/// CapCut-style audio panel:
///  - two action tiles (Music / Extract audio)
///  - volume card with mute toggle and a 100% marker
///  - speed card with slider and a segmented preset row
class AudioToolsSheet extends StatefulWidget {
  const AudioToolsSheet({super.key});

  @override
  State<AudioToolsSheet> createState() => _AudioToolsSheetState();
}

class _AudioToolsSheetState extends State<AudioToolsSheet> {
  static const _speedPresets = <double>[0.5, 0.75, 1.0, 1.5, 2.0];

  // Local drafts keep the sliders smooth while dragging.
  double? _volumeDraft;
  double? _speedDraft;
  double _volumeBeforeMute = 1.0;

  Future<void> _importAudio(EditorController editor) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      final file = result?.files.single;
      if (file == null || file.path == null) return;
      editor.addAudioTrack(file.path!, trackName: file.name);
    } catch (e) {
      _toast('Couldn\'t import audio');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: EditorTokens.elevated,
          duration: const Duration(seconds: 2),
          content: Text(msg,
              style: const TextStyle(color: EditorTokens.text, fontFamily: _font)),
        ),
      );
  }

  void _apply(EditorController editor,
      {required double volume, required double speed}) {
    editor.updateAudioProperties(AudioProperties(volume: volume, speed: speed));
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip =
        context.select<EditorController, TimelineClip?>((e) => e.selectedClip);

    final isVideo = clip?.clipType == ClipType.video;
    final isAudio = clip?.clipType == ClipType.audio;
    final hasAudio = isVideo || isAudio;

    final volume = (_volumeDraft ?? clip?.volume ?? 1.0).clamp(0.0, 2.0);
    final speed = (_speedDraft ?? clip?.speed ?? 1.0).clamp(0.5, 2.0);
    final muted = volume == 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: PhosphorIconsRegular.musicNotes,
                label: 'Music',
                caption: 'From device',
                onTap: () => _importAudio(editor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionTile(
                icon: PhosphorIconsRegular.scissors,
                label: 'Extract audio',
                caption: isVideo ? 'From selected clip' : 'Select a video',
                enabled: isVideo,
                onTap: () {
                  editor.extractAudioFromSelectedClip();
                  _toast('Audio extracted');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (!hasAudio)
          const _EmptyHint()
        else ...[
          _Section(
            title: 'Volume',
            value: '${(volume * 100).round()}%',
            child: Row(
              children: [
                _RoundIconButton(
                  icon: muted
                      ? PhosphorIconsRegular.speakerSlash
                      : PhosphorIconsRegular.speakerHigh,
                  active: muted,
                  onTap: () {
                    if (muted) {
                      final restore =
                          _volumeBeforeMute == 0 ? 1.0 : _volumeBeforeMute;
                      setState(() => _volumeDraft = null);
                      _apply(editor, volume: restore, speed: speed);
                    } else {
                      _volumeBeforeMute = volume;
                      setState(() => _volumeDraft = null);
                      _apply(editor, volume: 0, speed: speed);
                    }
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    children: [
                      _EditorSlider(
                        value: volume,
                        min: 0,
                        max: 2,
                        onChanged: (v) {
                          setState(() => _volumeDraft = v);
                          _apply(editor, volume: v, speed: speed);
                        },
                        onChangeEnd: (_) => setState(() => _volumeDraft = null),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _Tick('0'),
                            _Tick('100%'),
                            _Tick('200%'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Speed',
            value: _fmtSpeed(speed),
            child: Column(
              children: [
                _EditorSlider(
                  value: speed,
                  min: 0.5,
                  max: 2,
                  onChanged: (v) {
                    setState(() => _speedDraft = v);
                    _apply(editor, volume: volume, speed: v);
                  },
                  onChangeEnd: (_) => setState(() => _speedDraft = null),
                ),
                const SizedBox(height: 4),
                _Segmented(
                  labels: [for (final p in _speedPresets) _fmtSpeed(p)],
                  selectedIndex:
                      _speedPresets.indexWhere((p) => (speed - p).abs() < 0.01),
                  onSelected: (i) {
                    setState(() => _speedDraft = null);
                    _apply(editor, volume: volume, speed: _speedPresets[i]);
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── Components ─────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.enabled = true,
  });

  final PhosphorIconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color fg = enabled ? EditorTokens.text : EditorTokens.muted;
    return Material(
      color: EditorTokens.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled
                      ? _accent.withValues(alpha: 0.14)
                      : Colors.white10,
                ),
                child: Center(
                  child: PhosphorIcon(icon,
                      size: 20, color: enabled ? _accent : EditorTokens.muted),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: _font,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EditorTokens.muted,
                        fontSize: 11,
                        fontFamily: _font,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.value, required this.child});

  final String title;
  final String value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: EditorTokens.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: _font,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: _font,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: EditorTokens.muted,
          fontSize: 10,
          fontFamily: _font,
        ),
      );
}

class _EditorSlider extends StatelessWidget {
  const _EditorSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: _accent,
        inactiveTrackColor: Colors.white12,
        thumbColor: Colors.white,
        overlayColor: _accent.withValues(alpha: 0.16),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// Equal-width segmented control for speed presets.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: EditorTokens.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selectedIndex ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == selectedIndex ? Colors.black : EditorTokens.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: _font,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, this.active = false});

  final PhosphorIconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? _accent : Colors.white10,
        ),
        child: Center(
          child: PhosphorIcon(
            icon,
            size: 18,
            color: active ? Colors.black : EditorTokens.text,
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: EditorTokens.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          PhosphorIcon(PhosphorIconsRegular.waveform,
              color: EditorTokens.muted, size: 28),
          SizedBox(height: 10),
          Text(
            'Select an audio or video clip\nto adjust volume and speed',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EditorTokens.muted,
              fontSize: 12,
              height: 1.4,
              fontFamily: _font,
            ),
          ),
        ],
      ),
    );
  }
}