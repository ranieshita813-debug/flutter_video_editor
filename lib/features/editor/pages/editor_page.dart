import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/preview/overlay_layer.dart';
import 'package:flutter_video_editor/features/editor/preview/video_preview.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/timeline/timeline.dart';
import 'package:flutter_video_editor/features/editor/tool_panel/tool_panel.dart';
import 'package:flutter_video_editor/features/editor/toolbar/editor_toolbar.dart';
import 'package:flutter_video_editor/features/editor/toolbar/editor_toolbar_widget.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';

void _tap() => HapticFeedback.selectionClick();

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  EditorTool? _activeTool;
  double _panelFrac = 0.32;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      context.read<EditorController>().autosave();
    }
  }

  void _openTool(EditorTool tool) {
    _tap();
    setState(() => _activeTool = tool);
  }

  void _closeTool() {
    setState(() => _activeTool = null);
  }

  Future<bool> _onWillPop() async {
    final editor = context.read<EditorController>();
    if (_activeTool != null) {
      _closeTool();
      return false;
    }

    if (!editor.isDirty) return true;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EditorTokens.surface,
        title: const Text('Unsaved Changes', style: TextStyle(color: EditorTokens.text)),
        content: const Text('Do you want to save your changes before exiting?', style: TextStyle(color: EditorTokens.muted)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard', style: TextStyle(color: EditorTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel', style: TextStyle(color: EditorTokens.text)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EditorTokens.text,
              foregroundColor: EditorTokens.bg,
            ),
            onPressed: () {
              editor.markSaved();
              Navigator.of(context).pop('save');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == 'save' || result == 'discard') {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final double bottomKeyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bool isKeyboardOpen = bottomKeyboardInset > 0;
    final bool isTablet = MediaQuery.sizeOf(context).width >= 840;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool allow = await _onWillPop();
          if (allow && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: EditorTokens.bg,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final double totalH = constraints.maxHeight;

            if (isTablet) {
              return Row(
                children: <Widget>[
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Stack(
                            children: <Widget>[
                              VideoPlayerPreview(editor: editor),
                              OverlayLayer(editor: editor),
                              _buildTopBar(context),
                              _buildBottomPreviewControls(editor),
                            ],
                          ),
                        ),
                        Timeline(editor: editor, compact: false),
                      ],
                    ),
                  ),
                  Container(width: 1, color: EditorTokens.border),
                  SizedBox(
                    width: 360,
                    child: _activeTool == null
                        ? EditorToolbarWidget(onOpenTool: _openTool)
                        : ToolPanel(
                            tool: _activeTool!,
                            height: totalH,
                            onClose: _closeTool,
                            onResize: (_) {},
                            onDrag: (_) {},
                          ),
                  ),
                ],
              );
            }

            final double minPreviewH = totalH * 0.35;
            final double panelH = math.min(totalH * _panelFrac, totalH * 0.55).clamp(160.0, totalH - minPreviewH);

            return Column(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      VideoPlayerPreview(editor: editor),
                      OverlayLayer(editor: editor),
                      _buildTopBar(context),
                      _buildBottomPreviewControls(editor),
                    ],
                  ),
                ),
                if (!isKeyboardOpen || _activeTool == null)
                  Timeline(editor: editor, compact: _activeTool != null),
                AnimatedSize(
                  duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: _activeTool == null
                      ? EditorToolbarWidget(onOpenTool: _openTool)
                      : Padding(
                          padding: EdgeInsets.only(bottom: bottomKeyboardInset),
                          child: ToolPanel(
                            tool: _activeTool!,
                            height: panelH,
                            onClose: _closeTool,
                            onResize: (dy) => setState(() {
                              _panelFrac = (_panelFrac - dy / totalH).clamp(0.2, 0.6);
                            }),
                            onDrag: (v) => setState(() => _dragging = v),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: EditorTokens.text, size: 20),
                onPressed: () async {
                  final bool allow = await _onWillPop();
                  if (allow && context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: EditorTokens.elevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: EditorTokens.border),
                ),
                child: const Text('1080p', style: TextStyle(color: EditorTokens.text, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: EditorTokens.text,
                  foregroundColor: EditorTokens.bg,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () {
                  _tap();
                  ExportModal.show(context);
                },
                icon: const Icon(Icons.ios_share_rounded, size: 16),
                label: const Text('Export', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPreviewControls(EditorController editor) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ValueListenableBuilder<Duration>(
            valueListenable: editor.playheadNotifier,
            builder: (context, p, _) {
              final double sec = p.inMilliseconds / 1000.0;
              final double totalSec = editor.project.totalDuration.inMilliseconds / 1000.0;
              return Text.rich(
                TextSpan(
                  children: <TextSpan>[
                    TextSpan(
                      text: _formatTC(sec, editor.fps),
                      style: const TextStyle(
                        color: EditorTokens.text,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '  /  ${_formatTC(totalSec, editor.fps)}',
                      style: const TextStyle(
                        color: EditorTokens.muted,
                        fontSize: 12,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.undo_rounded, color: EditorTokens.text, size: 22),
                onPressed: editor.canUndo ? editor.undo : null,
              ),
              const SizedBox(width: 12),
              ListenableBuilder(
                listenable: editor,
                builder: (context, _) {
                  return GestureDetector(
                    onTap: () {
                      _tap();
                      editor.togglePlayback();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: EditorTokens.text, shape: BoxShape.circle),
                      child: Icon(
                        editor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: EditorTokens.bg,
                        size: 28,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.redo_rounded, color: EditorTokens.text, size: 22),
                onPressed: editor.canRedo ? editor.redo : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTC(double s, int fps) {
    final int f = (math.max(s, 0) * fps).round();
    final int sec = f ~/ fps;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(sec ~/ 3600)}:${two(sec % 3600 ~/ 60)}:${two(sec % 60)}:${two(f % fps)}';
  }
}
