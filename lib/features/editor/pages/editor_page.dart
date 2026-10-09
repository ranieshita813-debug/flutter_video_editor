import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/editor_toolbar.dart';
import 'package:flutter_video_editor/features/editor/widgets/preview.dart';
import 'package:flutter_video_editor/features/editor/widgets/timeline.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_panel.dart';
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
  double _frac = 0.34;
  double _splitAdj = 0, _minAdj = -400, _maxAdj = 400;
  bool _dragging = false;

  final ValueNotifier<bool> _multiOn = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> _multi = ValueNotifier<Set<String>>(<String>{});

  void _open(EditorTool t) {
    tapFeedback();
    setState(() => _tool = _tool == t ? null : t);
  }

  void _openSheet(String sheetName) {
    EditorTool? target;
    switch (sheetName) {
      case 'audio': target = EditorTool.audio; break;
      case 'text': target = EditorTool.text; break;
      case 'stickers': target = EditorTool.stickers; break;
      case 'filters': target = EditorTool.filters; break;
      case 'effects': target = EditorTool.effects; break;
      case 'adjust': target = EditorTool.adjust; break;
      case 'crop': target = EditorTool.crop; break;
      case 'speed': target = EditorTool.speed; break;
      case 'elements': target = EditorTool.elements; break;
      case 'draw': target = EditorTool.draw; break;
      case 'mask': target = EditorTool.mask; break;
      case 'camera': target = EditorTool.camera; break;
      case 'track': target = EditorTool.track; break;
      case 'text_style': target = EditorTool.textStyle; break;
      case 'animation': target = EditorTool.animation; break;
      case 'order': target = EditorTool.order; break;
      case 'chroma_key': target = EditorTool.chromaKey; break;
    }
    if (target != null) {
      _open(target);
    }
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
    if (mounted) setState(() => _splitAdj = 0);
  }

  @override
  void dispose() {
    canvasRatioNotifier.removeListener(_resetSplit);
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
        const SingleActivator(LogicalKeyboardKey.space): guardKeyboard(editor.togglePlayback),
        const SingleActivator(LogicalKeyboardKey.keyK): guardKeyboard(editor.togglePlayback),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            guardKeyboard(() => seekPlayhead(editor, secondsOf(editor.playhead) - 1 / fpsToken)),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            guardKeyboard(() => seekPlayhead(editor, secondsOf(editor.playhead) + 1 / fpsToken)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            guardKeyboard(() => seekPlayhead(editor, secondsOf(editor.playhead) - 1.0)),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            guardKeyboard(() => seekPlayhead(editor, secondsOf(editor.playhead) + 1.0)),
        const SingleActivator(LogicalKeyboardKey.keyS):
            guardKeyboard(() => splitAllTracks(editor)),
        const SingleActivator(LogicalKeyboardKey.delete): guardKeyboard(() {
          if (editor.selectedClip != null) editor.deleteSelectedClip();
        }),
        const SingleActivator(LogicalKeyboardKey.backspace): guardKeyboard(() {
          if (editor.selectedClip != null) editor.deleteSelectedClip();
        }),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): guardKeyboard(editor.undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): guardKeyboard(editor.undo),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): guardKeyboard(editor.redo),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
            guardKeyboard(editor.redo),
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
            child: Scaffold(
              backgroundColor: bgToken,
              resizeToAvoidBottomInset: true,
              body: LayoutBuilder(builder: (context, c) {
                // The panel never takes more than half of what is left, so an
                // open keyboard cannot squeeze the preview down to nothing.
                final double panelH = (c.maxHeight * _frac)
                    .clamp(160.0, math.max(160.0, c.maxHeight * 0.5))
                    .toDouble();
                final double sideW =
                    (c.maxWidth * 0.3).clamp(320.0, 440.0).toDouble();

                // On phones, an open tool sheet hides the timeline, divider
                // and transport bar so the preview gets all the space.
                final bool hideTimeline = _tool != null && !wide;

                final Widget toolbar = EditorToolbar(
                  key: const ValueKey('bar'),
                  onSelectToolSheet: _openSheet,
                  onAddMedia: () async {
                    final nav = Navigator.of(context);
                    await nav.pushNamed(
                      '/media_picker',
                      arguments: const MediaPickerArgs(appendToCurrent: true, isOverlay: false),
                    );
                  },
                  onAddOverlay: () async {
                    final nav = Navigator.of(context);
                    await nav.pushNamed(
                      '/media_picker',
                      arguments: const MediaPickerArgs(appendToCurrent: true, isOverlay: true),
                    );
                  },
                );

                final Widget main = Column(
                  children: <Widget>[
                    ValueListenableBuilder<CanvasRatio>(
                      valueListenable: canvasRatioNotifier,
                      builder: (context, ratio, _) {
                        final Widget pv = PreviewCanvas(editor: editor);
                        if (hideTimeline) {
                          // No transport bar here, so tap the preview to
                          // play / pause while tweaking a tool.
                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: editor.togglePlayback,
                              child: pv,
                            ),
                          );
                        }
                        final double s = scaleOf(size);
                        final EdgeInsets safe = MediaQuery.paddingOf(context);
                        final double colW = wide
                            ? c.maxWidth - (_tool != null ? sideW : 0)
                            : c.maxWidth;
                        final double topH = 52 * s + safe.top;
                        final double transportH = 52 * s + 16;
                        final double barH = (64 * s).clamp(60.0, 80.0).toDouble();
                        final double bottomH =
                            ((wide || _tool == null) ? barH : panelH) + safe.bottom;
                        final double tlMin = (isShort(size) ? 90 : 120) * s;
                        final double tlMax = 240 * s;
                        // Canvas is full width with square corners, so the
                        // wanted height is simply width / ratio (no padding).
                        final double desired = topH + colW / ratio.value;
                        final double maxP =
                            math.max(80.0, c.maxHeight - transportH - bottomH - tlMin);
                        final double minP = math.min(
                            maxP,
                            math.max(80.0,
                                c.maxHeight - transportH - bottomH - tlMax));
                        final double base = desired.clamp(minP, maxP).toDouble();
                        final double lo = math.min(
                            maxP, math.max(80.0, c.maxHeight - transportH - bottomH - 420 * s));
                        _minAdj = lo - base;
                        _maxAdj = maxP - base;
                        final double hgt =
                            (base + _splitAdj.clamp(_minAdj, _maxAdj)).toDouble();
                        return SizedBox(height: hgt, child: pv);
                      },
                    ),
                    if (!hideTimeline) TransportBar(editor: editor),
                    if (!hideTimeline)
                      PaneDivider(
                        onDrag: (dy) => setState(() => _splitAdj =
                            (_splitAdj + dy).clamp(_minAdj, _maxAdj).toDouble()),
                        onReset: () => setState(() => _splitAdj = 0),
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
                            children: <Widget>[...prev, if (cur != null) cur],
                          ),
                          child: _tool == null
                              ? toolbar
                              : ToolPanel(
                                  key: ValueKey<EditorTool>(_tool!),
                                  tool: _tool!,
                                  height: panelH,
                                  onClose: _close,
                                  onResize: (dy) => setState(() {
                                    _frac = (_frac - dy / c.maxHeight)
                                        .clamp(0.22, 0.6)
                                        .toDouble();
                                  }),
                                  onDrag: (v) => setState(() => _dragging = v),
                                ),
                        ),
                      ),
                  ],
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
    );
  }
}