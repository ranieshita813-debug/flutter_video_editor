import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

/// CapCut-style audio panel:
///  - two big action tiles (Music / Extract)
///  - contextual controls (volume + mute, speed presets) for the selected clip
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
      _toast('Could not import audio');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _apply(EditorController editor, {required double volume, required double speed}) {
    editor.updateAudioProperties(AudioProperties(volume: volume, speed: speed));
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);

    final isVideo = clip?.clipType == ClipType.video;
    final isAudio = clip?.clipType == ClipType.audio;
    final hasAudio = isVideo || isAudio;

    final volume = (_volumeDraft ?? clip?.volume ?? 1.0).clamp(0.0, 2.0);
    final speed = (_speedDraft ?? clip?.speed ?? 1.0).clamp(0.5, 2.0);
    final muted = volume == 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ── Primary actions ────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: PhosphorIconsRegular.musicNotes,
                label: 'Music',
                caption: 'Import from device',
                onTap: () => _importAudio(editor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionTile(
                icon: PhosphorIconsRegular.scissors,
                label: 'Extract audio',
                caption: isVideo ? 'From selected video' : 'Select a video clip',
                enabled: isVideo,
                onTap: () {
                  editor.extractAudioFromSelectedClip();
                  _toast('Audio extracted');
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── Contextual controls ────────────────────────────────────────
        if (!hasAudio)
          const _EmptyHint()
        else ...[
          _Section(
            title: 'Volume',
            trailing: '${(volume * 100).round()}%',
            child: Row(
              children: [
                _RoundIconButton(
                  icon: muted
                      ? PhosphorIconsRegular.speakerSlash
                      : PhosphorIconsRegular.speakerHigh,
                  active: muted,
                  onTap: () {
                    if (muted) {
                      final restore = _volumeBeforeMute == 0 ? 1.0 : _volumeBeforeMute;
                      setState(() => _volumeDraft = null);
                      _apply(editor, volume: restore, speed: speed);
                    } else {
                      _volumeBeforeMute = volume;
                      setState(() => _volumeDraft = null);
                      _apply(editor, volume: 0, speed: speed);
                    }
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _EditorSlider(
                    value: volume,
                    min: 0,
                    max: 2,
                    onChanged: (v) {
                      setState(() => _volumeDraft = v);
                      _apply(editor, volume: v, speed: speed);
                    },
                    onChangeEnd: (_) => setState(() => _volumeDraft = null),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Speed',
            trailing: '${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}x',
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
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final p in _speedPresets)
                      _Chip(
                        label: '${p}x',
                        selected: (speed - p).abs() < 0.01,
                        onTap: () {
                          setState(() => _speedDraft = null);
                          _apply(editor, volume: volume, speed: p);
                        },
                      ),
                  ],
                ),
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
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: EditorTokens.elevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EditorTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhosphorIcon(icon, color: EditorTokens.text, size: 24),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: EditorTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Ubuntu',
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
                    fontFamily: 'Ubuntu',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.trailing, required this.child});

  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: EditorTokens.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EditorTokens.border),
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
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Ubuntu',
                ),
              ),
              Text(
                trailing,
                style: const TextStyle(
                  color: EditorTokens.muted,
                  fontSize: 12,
                  fontFamily: 'Ubuntu',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
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
        activeTrackColor: EditorTokens.text,
        inactiveTrackColor: EditorTokens.border,
        thumbColor: EditorTokens.text,
        overlayColor: EditorTokens.text.withOpacity(0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? EditorTokens.text : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? EditorTokens.text : EditorTokens.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? EditorTokens.bg : EditorTokens.text,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Ubuntu',
          ),
        ),
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
          color: active ? EditorTokens.text : Colors.transparent,
          border: Border.all(color: active ? EditorTokens.text : EditorTokens.border),
        ),
        child: Center(
          child: PhosphorIcon(
            icon,
            size: 18,
            color: active ? EditorTokens.bg : EditorTokens.text,
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EditorTokens.border),
      ),
      child: const Column(
        children: [
          PhosphorIcon(PhosphorIconsRegular.waveform, color: EditorTokens.muted, size: 28),
          SizedBox(height: 10),
          Text(
            'Select an audio or video clip\nto adjust volume and speed',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EditorTokens.muted,
              fontSize: 12,
              height: 1.4,
              fontFamily: 'Ubuntu',
            ),
          ),
        ],
      ),
    );
  }
}