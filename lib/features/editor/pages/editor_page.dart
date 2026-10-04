import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart'
    show EditorController;

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
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: _EditorWorkspace(editor: editor),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 300,
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.movie_creation_outlined, color: Color(0xFF8B5CF6)),
          const SizedBox(width: 12),
          const Text(
            'Video Editor Pro',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          _ToolButton(icon: Icons.undo_rounded, label: 'Undo'),
          _ToolButton(icon: Icons.redo_rounded, label: 'Redo'),
          _ToolButton(icon: Icons.save_alt_rounded, label: 'Export'),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: editor.togglePlayback,
            icon: Icon(
              editor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(editor.isPlaying ? 'Pause' : 'Preview'),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _EditorWorkspace extends StatelessWidget {
  const _EditorWorkspace({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
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
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF1F2937),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.videocam_outlined, size: 64, color: Colors.white70),
                    const SizedBox(height: 12),
                    const Text(
                      'Preview Canvas',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Playhead: ${EditorUtils.formatDuration(editor.playhead)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _QuickAction(
                  icon: Icons.cut_rounded,
                  label: 'Cut',
                  onTap: () => editor.splitSelectedClip(),
                ),
                _QuickAction(
                  icon: Icons.content_cut_rounded,
                  label: 'Split',
                  onTap: () => editor.splitSelectedClip(),
                ),
                _QuickAction(
                  icon: Icons.text_fields_rounded,
                  label: 'Text',
                  onTap: () => editor.addTextOverlay('Title Text'),
                ),
                _QuickAction(
                  icon: Icons.filter_alt_rounded,
                  label: 'Filters',
                  onTap: () => editor.applyEffect(VideoEffect.cinematic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF374151)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: const Color(0xFF8B5CF6)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
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
    final clip = editor.project.clips.firstWhere(
      (TimelineClip item) => item.id == editor.selectedClipId,
      orElse: () => editor.project.clips.first,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Inspector',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          _InspectorOption(title: 'Selected', value: clip.label),
          _InspectorOption(title: 'Trim', value: '${EditorUtils.formatDuration(clip.start)}-${EditorUtils.formatDuration(clip.end)}'),
          _InspectorOption(title: 'Speed', value: '${clip.speed.toStringAsFixed(1)}x'),
          _InspectorOption(title: 'Volume', value: '${(clip.volume * 100).round()}%'),
          _InspectorOption(title: 'Filters', value: clip.effect.name),
          _InspectorOption(title: 'Transitions', value: 'Fade'),
          const SizedBox(height: 18),
          const Text(
            'Advanced tools ready',
            style: TextStyle(
              color: Color(0xFF8B5CF6),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(title, style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
      height: 250,
      padding: const EdgeInsets.all(16),
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
                  'Timeline',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              _ToolButton(icon: Icons.timeline_rounded, label: 'Track'),
              _ToolButton(icon: Icons.voice_chat_rounded, label: 'Audio'),
              _ToolButton(icon: Icons.filter_alt_rounded, label: 'FX'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(18),
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
                    ClipType.image => const Color(0xFFF59E0B),
                    ClipType.sticker => const Color(0xFFF472B6),
                  };

                  return GestureDetector(
                    onTap: () => editor.selectClip(clip.id),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF0F172A),
                        border: Border.all(
                          color: editor.selectedClipId == clip.id
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFF0F172A),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${clip.label} • ${clip.clipType.name}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              _ClipBlock(
                                color: color,
                                label: clip.label,
                                width: 180,
                              ),
                            ],
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

class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.color,
    required this.label,
    required this.width,
  });

  final Color color;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: width,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
