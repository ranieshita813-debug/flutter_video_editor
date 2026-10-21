import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/editor_toolbar.dart';
import 'package:flutter_video_editor/features/editor/widgets/preview.dart';
import 'package:flutter_video_editor/features/editor/widgets/timeline.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_panel.dart';
import 'package:flutter_video_editor/core/services/ai_generation_service.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/ai/gen.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';
import 'package:flutter_video_editor/features/editor/widgets/transport.dart';
import 'package:flutter_video_editor/features/media_picker/pages/media_picker_page.dart';

// ----------------------------------------------------------------------------
// Page
// ----------------------------------------------------------------------------
class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  EditorTool? _tool;
  final ValueNotifier<double> _fracNotifier = ValueNotifier<double>(0.34);
  final ValueNotifier<double> _splitAdjNotifier = ValueNotifier<double>(0.0);
  double _minAdj = -400, _maxAdj = 400;
  bool _dragging = false;

  final ValueNotifier<bool> _multiOn = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> _multi =
      ValueNotifier<Set<String>>(<String>{});

  void _open(EditorTool t) {
    tapFeedback();
    setState(() => _tool = _tool == t ? null : t);
  }

  void _openSheet(String sheetName) {
    if (sheetName == 'ai' || sheetName == 'ai_generate') {
      _openAiGenerateSheet();
      return;
    }
    final target = switch (sheetName) {
      'audio' => EditorTool.audio,
      'text' => EditorTool.text,
      'text_to_speech' => EditorTool.textToSpeech,
      'stickers' => EditorTool.stickers,
      'filters' => EditorTool.filters,
      'effects' => EditorTool.effects,
      'adjust' => EditorTool.adjust,
      'crop' => EditorTool.crop,
      'speed' => EditorTool.speed,
      'elements' => EditorTool.elements,
      'draw' => EditorTool.draw,
      'mask' => EditorTool.mask,
      'camera' => EditorTool.camera,
      'track' => EditorTool.track,
      'text_style' => EditorTool.textStyle,
      'animation' => EditorTool.animation,
      'order' => EditorTool.order,
      'chroma_key' => EditorTool.chromaKey,
      'captions' || 'captions_edit' => EditorTool.captions,
      'captions_style' => EditorTool.captionsStyle,
      'caption_translate' ||
      'captions_translate' =>
        EditorTool.captionsTranslate,
      _ => null,
    };
    if (target != null) {
      _open(target);
    }
  }

  void _openAiGenerateSheet() {
    tapFeedback();
    final editor = context.read<EditorController>();
    showAiGenerateSheet(
      context,
      onGenerate: (AiGenerationRequest request) =>
          handleAiGeneration(context, editor, request),
    );
  }

  void _close() => setState(() => _tool = null);

  void _clearMulti() {
    _multiOn.value = false;
    _multi.value = <String>{};
  }

  @override
  void initState() {
    super.initState();
    canvasRatioNotifier.addListener(_resetSplit);
  }

  void _resetSplit() {
    if (mounted) _splitAdjNotifier.value = 0.0;
  }

  @override
  void dispose() {
    canvasRatioNotifier.removeListener(_resetSplit);
    _fracNotifier.dispose();
    _splitAdjNotifier.dispose();
    _multiOn.dispose();
    _multi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final Size size = MediaQuery.sizeOf(context);
    final bool wide = isWide(size);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space):
            guardKeyboard(editor.togglePlayback),
        const SingleActivator(LogicalKeyboardKey.keyK):
            guardKeyboard(editor.togglePlayback),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): guardKeyboard(() =>
            seekPlayhead(editor, secondsOf(editor.playhead) - 1 / fpsToken)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): guardKeyboard(
            () => seekPlayhead(
                editor, secondsOf(editor.playhead) + 1 / fpsToken)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            guardKeyboard(
                () => seekPlayhead(editor, secondsOf(editor.playhead) - 1.0)),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            guardKeyboard(
                () => seekPlayhead(editor, secondsOf(editor.playhead) + 1.0)),
        const SingleActivator(LogicalKeyboardKey.keyS):
            guardKeyboard(() => splitAllTracks(editor)),
        const SingleActivator(LogicalKeyboardKey.delete): guardKeyboard(() {
          if (editor.selectedClip != null) editor.deleteSelectedClip();
        }),
        const SingleActivator(LogicalKeyboardKey.backspace): guardKeyboard(() {
          if (editor.selectedClip != null) editor.deleteSelectedClip();
        }),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            guardKeyboard(editor.undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            guardKeyboard(editor.undo),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            guardKeyboard(editor.redo),
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): guardKeyboard(editor.redo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            guardKeyboard(editor.redo),
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _multiOn,
          builder: (context, _) => PopScope(
            canPop: _tool == null && !_multiOn.value,
            onPopInvokedWithResult: (bool didPop, dynamic result) {
              if (didPop) return;
              if (_multiOn.value) {
                _clearMulti();
              } else {
                _close();
              }
            },
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: bgToken,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: bgToken,
                systemNavigationBarIconBrightness: Brightness.light,
                systemNavigationBarDividerColor: bgToken,
              ),
              child: Scaffold(
                backgroundColor: bgToken,
                resizeToAvoidBottomInset: true,
                body: LayoutBuilder(builder: (context, c) {
                  final double sideW =
                      (c.maxWidth * 0.3).clamp(320.0, 440.0).toDouble();
                  final bool hideTimeline = _tool != null && !wide;

                  final Widget toolbar = EditorToolbar(
                    key: const ValueKey('bar'),
                    onSelectToolSheet: _openSheet,
                    onAddMedia: () async {
                      final nav = Navigator.of(context);
                      await nav.pushNamed(
                        '/media_picker',
                        arguments: const MediaPickerArgs(
                            appendToCurrent: true, isOverlay: false),
                      );
                    },
                    onAddOverlay: () async {
                      final nav = Navigator.of(context);
                      await nav.pushNamed(
                        '/media_picker',
                        arguments: const MediaPickerArgs(
                            appendToCurrent: true, isOverlay: true),
                      );
                    },
                  );

                  final Widget main = ValueListenableBuilder<double>(
                    valueListenable: _fracNotifier,
                    builder: (context, frac, _) {
                      final double panelH = (c.maxHeight * frac)
                          .clamp(160.0, math.max(160.0, c.maxHeight * 0.5))
                          .toDouble();

                      final double s = scaleOf(size);
                      final EdgeInsets safe = MediaQuery.paddingOf(context);
                      final double colW = wide
                          ? c.maxWidth - (_tool != null ? sideW : 0)
                          : c.maxWidth;
                      final double topH = 52 * s + safe.top;
                      final double transportH = 52 * s + 16;
                      final double barH = (64 * s).clamp(60.0, 80.0).toDouble();
                      final double bottomH =
                          ((wide || _tool == null) ? barH : panelH) +
                              safe.bottom;
                      final double tlMin = (isShort(size) ? 90 : 120) * s;
                      final double tlMax = 240 * s;

                      return ValueListenableBuilder<CanvasRatio>(
                        valueListenable: canvasRatioNotifier,
                        builder: (context, ratio, _) {
                          final double desired = topH + colW / ratio.value;
                          final double maxP = math.max(
                              80.0, c.maxHeight - transportH - bottomH - tlMin);
                          final double minP = math.min(
                              maxP,
                              math.max(80.0,
                                  c.maxHeight - transportH - bottomH - tlMax));
                          final double base =
                              desired.clamp(minP, maxP).toDouble();

                          _minAdj = math.min(0.0, (desired - base).toDouble());
                          _maxAdj = math.max(0.0, (maxP - base).toDouble());

                          return Column(
                            children: <Widget>[
                              if (hideTimeline)
                                Expanded(
                                  child: PreviewCanvas(editor: editor),
                                )
                              else
                                ValueListenableBuilder<double>(
                                  valueListenable: _splitAdjNotifier,
                                  builder: (context, splitAdj, _) {
                                    final double hgt = (base +
                                            splitAdj.clamp(_minAdj, _maxAdj))
                                        .toDouble();
                                    return SizedBox(
                                        height: hgt,
                                        child: PreviewCanvas(editor: editor));
                                  },
                                ),
                              if (!hideTimeline) TransportBar(editor: editor),
                              if (!hideTimeline)
                                PaneDivider(
                                  onDrag: (dy) => _splitAdjNotifier.value =
                                      (_splitAdjNotifier.value + dy)
                                          .clamp(_minAdj, _maxAdj)
                                          .toDouble(),
                                  onReset: () => _splitAdjNotifier.value = 0.0,
                                ),
                              if (!hideTimeline)
                                Expanded(
                                  child: TimelineWidget(
                                    editor: editor,
                                    compact: false,
                                    multiOn: _multiOn,
                                    multi: _multi,
                                    onClearMulti: _clearMulti,
                                  ),
                                ),
                              if (wide)
                                toolbar
                              else
                                AnimatedSize(
                                  duration: _dragging
                                      ? Duration.zero
                                      : const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    layoutBuilder: (cur, prev) => Stack(
                                      alignment: Alignment.bottomCenter,
                                      children: <Widget>[
                                        ...prev,
                                        if (cur != null) cur
                                      ],
                                    ),
                                    child: _tool == null
                                        ? toolbar
                                        : ToolPanel(
                                            key: ValueKey<EditorTool>(_tool!),
                                            tool: _tool!,
                                            height: panelH,
                                            onClose: _close,
                                            onResize: (dy) {
                                              _fracNotifier.value =
                                                  (_fracNotifier.value -
                                                          dy / c.maxHeight)
                                                      .clamp(0.22, 0.6)
                                                      .toDouble();
                                            },
                                            onDrag: (v) =>
                                                setState(() => _dragging = v),
                                          ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  );

                  if (!wide) return main;

                  return Row(
                    children: <Widget>[
                      Expanded(child: main),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.centerRight,
                        child: _tool == null
                            ? const SizedBox(width: 0, height: 0)
                            : SizedBox(
                                width: sideW,
                                height: c.maxHeight,
                                child: ToolPanel(
                                  key: ValueKey<EditorTool>(_tool!),
                                  tool: _tool!,
                                  docked: true,
                                  onClose: _close,
                                ),
                              ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
