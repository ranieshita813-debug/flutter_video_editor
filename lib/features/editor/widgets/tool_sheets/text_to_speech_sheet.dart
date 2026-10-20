import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/google_tts_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

/// CapCut-style "Text to speech" bottom sheet.
///
/// Layout (top -> bottom):
///  1. Drag handle
///  2. Header: close (X)  |  title  |  confirm (check)
///  3. Text input card with character counter + clear button
///  4. "Voices" label + 3-column voice grid (scrollable)
///  5. Pinned bottom action bar with the primary button
class TextToSpeechSheet extends StatefulWidget {
  const TextToSpeechSheet({super.key});

  @override
  State<TextToSpeechSheet> createState() => _TextToSpeechSheetState();
}

class _TextToSpeechSheetState extends State<TextToSpeechSheet> {
  static const int _maxChars = 500;
  static const Color _accent = Color(0xFF25F4EE); // CapCut cyan
  static const String _font = 'Google Sans';

  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GoogleTtsService _ttsService = GoogleTtsService();

  String _selectedVoice = GoogleTtsService.voices.first;
  bool _isGenerating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editor = context.read<EditorController>();
      final clip = editor.selectedClip;
      if (clip != null) {
        _textController.text = clip.label;
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _generateSpeech() async {
    final String text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Enter some text first.');
      return;
    }
    _focusNode.unfocus();

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final editor = context.read<EditorController>();
      final clip = editor.selectedClip;
      final Duration startTime = clip?.start ?? editor.playhead;

      final String audioPath =
          await _ttsService.textToSpeech(text, voiceName: _selectedVoice);

      int durationMs = 3000;
      try {
        final meta = await ExportService().probe(audioPath);
        if (meta['durationMs'] != null && meta['durationMs'] is num) {
          durationMs = (meta['durationMs'] as num).toInt();
        }
      } catch (_) {}

      final String audioId = 'tts_${DateTime.now().millisecondsSinceEpoch}';
      editor.addClip(
        TimelineClip(
          id: audioId,
          label: 'Speech ($_selectedVoice)',
          start: startTime,
          end: startTime + Duration(milliseconds: durationMs),
          clipType: ClipType.audio,
          sourcePath: audioPath,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: EditorTokens.surface,
            duration: const Duration(seconds: 2),
            content: const Text(
              'Speech added to timeline',
              style: TextStyle(color: Colors.white, fontFamily: _font),
            ),
          ),
        );
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Couldn\'t generate speech. $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canGenerate =
        !_isGenerating && _textController.text.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: EditorTokens.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(canGenerate),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildTextCard()),
                  if (_errorMessage != null)
                    SliverToBoxAdapter(child: _buildError()),
                  const SliverToBoxAdapter(child: _SectionLabel('Voices')),
                  _buildVoiceGrid(),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
            _buildActionBar(canGenerate),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );

  Widget _buildHeader(bool canGenerate) => SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Expanded(
              child: Text(
                'Text to speech',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: _font,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.check_rounded,
                color: canGenerate ? _accent : Colors.white24,
              ),
              onPressed: canGenerate ? _generateSpeech : null,
            ),
          ],
        ),
      );

  Widget _buildTextCard() {
    final int count = _textController.text.characters.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
      decoration: BoxDecoration(
        color: EditorTokens.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextField(
            controller: _textController,
            focusNode: _focusNode,
            minLines: 3,
            maxLines: 5,
            maxLength: _maxChars,
            cursorColor: _accent,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
              fontFamily: _font,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              counterText: '',
              hintText: 'Type or paste the text you want to hear…',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontFamily: _font,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$count/$_maxChars',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: _font,
                ),
              ),
              const Spacer(),
              if (count > 0)
                GestureDetector(
                  onTap: () => _textController.clear(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.cancel_rounded,
                        size: 18, color: Colors.white38),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontFamily: _font,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildVoiceGrid() {
    final voices = GoogleTtsService.voices;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.25,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final String v = voices[i];
            return _VoiceTile(
              name: v,
              selected: v == _selectedVoice,
              accent: _accent,
              onTap: () => setState(() => _selectedVoice = v),
            );
          },
          childCount: voices.length,
        ),
      ),
    );
  }

  Widget _buildActionBar(bool canGenerate) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: EditorTokens.bg,
          border: Border(top: BorderSide(color: EditorTokens.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: _accent,
              disabledBackgroundColor: EditorTokens.surface,
              foregroundColor: Colors.black,
              disabledForegroundColor: Colors.white38,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(23),
              ),
            ),
            onPressed: canGenerate ? _generateSpeech : null,
            child: _isGenerating
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      ),
                      SizedBox(width: 10),
                      Text('Generating…',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFamily: _font)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      PhosphorIcon(PhosphorIconsRegular.waveSquare, size: 20),
                      SizedBox(width: 8),
                      Text('Add to timeline',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              fontFamily: _font)),
                    ],
                  ),
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'Google Sans',
          ),
        ),
      );
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.name,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : EditorTokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.white12,
              ),
              child: Icon(
                selected ? Icons.graphic_eq_rounded : Icons.person_rounded,
                size: 18,
                color: selected ? Colors.black : Colors.white54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? accent : Colors.white,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontFamily: 'Google Sans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}