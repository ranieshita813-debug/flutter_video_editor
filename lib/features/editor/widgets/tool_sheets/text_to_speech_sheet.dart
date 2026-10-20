import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/google_tts_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

class TextToSpeechSheet extends StatefulWidget {
  const TextToSpeechSheet({super.key});

  @override
  State<TextToSpeechSheet> createState() => _TextToSpeechSheetState();
}

class _TextToSpeechSheetState extends State<TextToSpeechSheet> {
  final TextEditingController _textController = TextEditingController();
  final GoogleTtsService _ttsService = GoogleTtsService();

  String _selectedVoice = GoogleTtsService.voices.first;
  bool _isGenerating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _generateSpeech() async {
    final String text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please enter text to generate speech.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final editor = context.read<EditorController>();
      final clip = editor.selectedClip;
      final Duration startTime = clip?.start ?? editor.playhead;

      final String audioPath = await _ttsService.textToSpeech(text, voiceName: _selectedVoice);

      int durationMs = 3000;
      try {
        final meta = await ExportService().probe(audioPath);
        if (meta['durationMs'] != null && meta['durationMs'] is num) {
          durationMs = (meta['durationMs'] as num).toInt();
        }
      } catch (_) {}

      final Duration audioDuration = Duration(milliseconds: durationMs);

      final String audioId = 'tts_${DateTime.now().millisecondsSinceEpoch}';
      final TimelineClip speechClip = TimelineClip(
        id: audioId,
        label: 'Speech ($_selectedVoice)',
        start: startTime,
        end: startTime + audioDuration,
        clipType: ClipType.audio,
        sourcePath: audioPath,
      );

      editor.addClip(speechClip);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Text to speech audio added to timeline!',
              style: TextStyle(fontFamily: 'Google Sans'),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Speech generation error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: EditorTokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Google AI Studio - Text to Speech',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Google Sans',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Google Sans'),
            decoration: InputDecoration(
              hintText: 'Enter text to convert into AI speech...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              filled: true,
              fillColor: EditorTokens.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: EditorTokens.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: EditorTokens.border),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'AI Voice:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Google Sans',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: GoogleTtsService.voices.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final v = GoogleTtsService.voices[idx];
                      final bool isSel = v == _selectedVoice;
                      return ChoiceChip(
                        label: Text(
                          v,
                          style: TextStyle(
                            color: isSel ? Colors.black : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Google Sans',
                          ),
                        ),
                        selected: isSel,
                        selectedColor: Colors.white,
                        backgroundColor: EditorTokens.surface,
                        onSelected: (_) => setState(() => _selectedVoice = v),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Google Sans'),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isGenerating ? null : _generateSpeech,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const PhosphorIcon(PhosphorIconsRegular.waveSquare, size: 20),
              label: Text(
                _isGenerating ? 'Generating AI Speech...' : 'Convert to Speech',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'Google Sans',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
