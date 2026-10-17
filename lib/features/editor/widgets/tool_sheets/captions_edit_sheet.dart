import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/core/widgets/caption_widgets.dart';

/// Sheet 1 of 2: edit caption text and timing. Styling lives in
/// [CaptionStyleSheet].
class CaptionsEditSheet extends StatefulWidget {
  const CaptionsEditSheet({super.key, this.onOpenStyle});

  /// Called when the user taps "Style". Wire this to open [CaptionStyleSheet].
  final VoidCallback? onOpenStyle;

  @override
  State<CaptionsEditSheet> createState() => _CaptionsEditSheetState();
}

class _CaptionsEditSheetState extends State<CaptionsEditSheet> {
  static const double _rowExtent = 116;

  final ScrollController _scroll = ScrollController();
  bool _isGenerating = false;
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _generate(EditorController editor) async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);
    tapFeedback();
    try {
      await editor.generateWhisperCaptions();
      if (!mounted) return;
      final n = editor.project.captions.length;
      _toast('Generated $n caption${n == 1 ? '' : 's'}');
    } catch (e) {
      if (!mounted) return;
      _toast('Auto captions failed: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _import(EditorController editor) async {
    tapFeedback();
    try {
      final count = await editor.importCaptionFile();
      if (!mounted || count <= 0) return;
      _toast('Imported $count caption${count == 1 ? '' : 's'}');
    } catch (e) {
      if (!mounted) return;
      _toast('Import failed: $e');
    }
  }

  void _addCue(EditorController editor) {
    tapFeedback();
    editor.addCaptionCue(
      CaptionCue(
        id: 'cue_${DateTime.now().microsecondsSinceEpoch}',
        start: editor.playhead,
        end: editor.playhead + const Duration(seconds: 3),
        text: 'New caption',
      ),
    );
  }

  /// Make timeline actions (split/merge) target this cue.
  /// NOTE: adapt `selectClip` to your controller's selection method.
  void _selectCue(EditorController editor, CaptionCue cue) {
    editor.selectClip('caption_${cue.id}');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _autoScrollTo(int index) {
    if (index < 0 || index == _lastActiveIndex) return;
    _lastActiveIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (index * _rowExtent - _rowExtent)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final captions = editor.project.captions;

    return Container(
      color: EditorTokens.surface,
      child: Column(
        children: [
          MonoSheetHeader(
            title: 'Captions',
            trailing: widget.onOpenStyle == null
                ? null
                : MonoButton(
                    label: 'Style',
                    icon: PhosphorIconsRegular.textAa,
                    onTap: widget.onOpenStyle,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: MonoButton(
                    filled: true,
                    expand: true,
                    busy: _isGenerating,
                    icon: PhosphorIconsRegular.sparkle,
                    label: _isGenerating ? 'Generating…' : 'Auto captions',
                    onTap: _isGenerating ? null : () => _generate(editor),
                  ),
                ),
                const SizedBox(width: 8),
                MonoButton(
                  label: 'Import',
                  icon: PhosphorIconsRegular.fileArrowUp,
                  onTap: () => _import(editor),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: EditorTokens.border),
          Expanded(
            child: captions.isEmpty
                ? _empty(editor)
                : _list(editor, captions),
          ),
        ],
      ),
    );
  }

  Widget _empty(EditorController editor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(PhosphorIconsRegular.closedCaptioning,
                size: 48, color: EditorTokens.muted),
            const SizedBox(height: 14),
            const Text('No captions yet',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: CaptionMono.font)),
            const SizedBox(height: 6),
            const Text(
              'Generate captions from speech, import an\n.srt or .vtt file, or add one by hand.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: EditorTokens.muted,
                  fontSize: 12.5,
                  height: 1.4,
                  fontFamily: CaptionMono.font),
            ),
            const SizedBox(height: 18),
            MonoButton(
              label: 'Add caption',
              icon: PhosphorIconsRegular.plus,
              onTap: () => _addCue(editor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(EditorController editor, List<CaptionCue> captions) {
    final p = editor.playhead;
    final active = captions.indexWhere((c) => p >= c.start && p < c.end);
    _autoScrollTo(active);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemExtent: _rowExtent,
      itemCount: captions.length + 1,
      itemBuilder: (context, i) {
        if (i == captions.length) {
          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: MonoButton(
                label: 'Add caption at playhead',
                icon: PhosphorIconsRegular.plus,
                onTap: () => _addCue(editor),
              ),
            ),
          );
        }
        final cue = captions[i];
        return _CueRow(
          key: ValueKey(cue.id),
          cue: cue,
          index: i + 1,
          active: i == active,
          onSeek: () {
            tapFeedback();
            seekPlayhead(editor, secondsOf(cue.start));
          },
          onTextChanged: (t) => editor.updateCaptionCue(cue.copyWith(text: t)),
          onSplit: () {
            tapFeedback();
            _selectCue(editor, cue);
            editor.splitSelectedClip();
          },
          onMerge: i == captions.length - 1
              ? null
              : () {
                  tapFeedback();
                  _selectCue(editor, cue);
                  editor.mergeNextCaptionClip();
                },
          onDelete: () {
            tapFeedback();
            editor.deleteCaptionCue(cue.id);
          },
        );
      },
    );
  }
}

class _CueRow extends StatelessWidget {
  const _CueRow({
    super.key,
    required this.cue,
    required this.index,
    required this.active,
    required this.onSeek,
    required this.onTextChanged,
    required this.onSplit,
    required this.onMerge,
    required this.onDelete,
  });

  final CaptionCue cue;
  final int index;
  final bool active;
  final VoidCallback onSeek;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onSplit;
  final VoidCallback? onMerge;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        decoration: BoxDecoration(
          color: active ? EditorTokens.elevated : Colors.transparent,
          borderRadius: BorderRadius.circular(CaptionMono.radius),
          border: Border.all(
            color: active ? Colors.white : EditorTokens.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSeek,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$index',
                            style: TextStyle(
                                color: active ? Colors.white : EditorTokens.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                fontFamily: CaptionMono.font)),
                        const SizedBox(width: 10),
                        Text(
                          '${formatCueTime(cue.start)} – ${formatCueTime(cue.end)}',
                          style: TextStyle(
                              color: active ? Colors.white : EditorTokens.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFamily: CaptionMono.font),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                _icon(PhosphorIconsRegular.scissors, 'Split', onSplit),
                _icon(PhosphorIconsRegular.arrowLineDown, 'Merge with next',
                    onMerge),
                _icon(PhosphorIconsRegular.trash, 'Delete', onDelete,
                    color: Colors.redAccent),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: TextFormField(
                  initialValue: cue.text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: Colors.white,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.3,
                      fontFamily: CaptionMono.font),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.only(right: 8),
                    hintText: 'Type caption…',
                    hintStyle: TextStyle(color: EditorTokens.muted),
                  ),
                  onChanged: onTextChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon, String tip, VoidCallback? onTap,
      {Color color = Colors.white70}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      tooltip: tip,
      onPressed: onTap,
      icon: PhosphorIcon(icon,
          size: 16, color: onTap == null ? Colors.white24 : color),
    );
  }
}