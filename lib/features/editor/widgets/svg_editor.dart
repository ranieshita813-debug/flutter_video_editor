import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:flutter_video_editor/core/models/svg_model.dart';

// ----------------------------------------------------------------------------
// Design tokens
// ----------------------------------------------------------------------------
const _accent = Color(0xFF9999FF);
const _panel = Color(0xFF232323);
const _panelHi = Color(0xFF2C2C2C);
const _bg = Color(0xFF181818);
const _line = Color(0x1FFFFFFF);
const _lbl = TextStyle(color: Color(0xFFB4B4B4), fontSize: 11, fontFamily: 'Ubuntu');
const _lblStrong = TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Ubuntu');

enum Tool { select, node, pen, pencil }

class SvgEditorPage extends StatefulWidget {
  const SvgEditorPage({super.key, required this.source, this.title = 'Untitled'});
  final String source, title;
  @override
  State<SvgEditorPage> createState() => _SvgEditorPageState();
}

class _SvgEditorPageState extends State<SvgEditorPage> with SingleTickerProviderStateMixin {
  late SvgDoc doc;
  final _undo = <SvgDoc>[], _redo = <SvgDoc>[];
  int sel = -1, ver = 0;
  String? error;

  // View
  double zoom = 0.9, _k = 1, _baseZoom = 0.9, _pinchScale0 = 1;
  Offset _pan = Offset.zero, _artTL = Offset.zero;
  bool _pinch = false;

  // Panel
  late final TabController tabs = TabController(length: 3, vsync: this);
  bool _panelOpen = true;
  int _lastTab = 0;

  // Tools
  Tool tool = Tool.select;
  PathModel? pm; // path being node-edited
  int selSp = 0, selAi = -1; // selected subpath / anchor
  int _drag = 0; // 0 none, 1 anchor, 2 in-handle, 3 out-handle
  bool _dragSnapped = false;
  List<Anchor> penA = [];
  bool _penDragging = false;
  List<Offset> pencilPts = [];

  // Cached serialisation so we don't re-serialise on every frame.
  String? _svgCache;
  int _svgVer = -1;
  String get svg {
    if (_svgCache == null || _svgVer != ver) {
      _svgCache = doc.toSvg();
      _svgVer = ver;
    }
    return _svgCache!;
  }

  static const _swatches = [
    0xFFFFFFFF, 0xFF000000, 0xFF9999FF, 0xFF2D8CFF, 0xFF00C2A8,
    0xFFFFC107, 0xFFFF7043, 0xFFEF5350, 0xFFE040FB,
  ];

  SvgNode? get cur => (sel >= 0 && sel < doc.nodes.length) ? doc.nodes[sel] : null;

  Anchor? get _selAnchor {
    final p = pm;
    if (p == null || selSp < 0 || selSp >= p.subs.length) return null;
    final a = p.subs[selSp].a;
    if (selAi < 0 || selAi >= a.length) return null;
    return a[selAi];
  }

  @override
  void initState() {
    super.initState();
    try {
      doc = SvgDoc.parse(widget.source, allowEmpty: true);
    } catch (e) {
      doc = SvgDoc(const Rect.fromLTWH(0, 0, 100, 100), '', []);
      error = '$e';
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  // ── history ──
  void snap() {
    _undo.add(doc.clone());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void edit(VoidCallback f) {
    snap();
    setState(() {
      f();
      ver++;
    });
  }

  void live(VoidCallback f) => setState(() {
        f();
        ver++;
      });

  void _syncPm() {
    final n = cur;
    pm = (tool == Tool.node && n != null && n.tag == 'path') ? PathModel.fromD(n.attrs['d'] ?? '') : null;
    if (pm == null || selSp >= pm!.subs.length) {
      selSp = 0;
      selAi = -1;
    } else if (selAi >= pm!.subs[selSp].a.length) {
      selAi = -1;
    }
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(doc.clone());
    setState(() {
      doc = _undo.removeLast();
      ver++;
      _syncPm();
    });
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(doc.clone());
    setState(() {
      doc = _redo.removeLast();
      ver++;
      _syncPm();
    });
  }

  // ── tools ──
  void _setTool(Tool t) {
    final pend = (tool == Tool.pen && penA.length >= 2) ? List<Anchor>.of(penA) : null;
    penA = [];
    pencilPts = [];
    if (pend != null) _addPathNode(pend, false, edit: false);
    var blocked = false;
    setState(() {
      tool = t;
      pm = null;
      selAi = -1;
      if (t == Tool.node) {
        if (cur == null) {
          tool = Tool.select;
          blocked = true;
        } else {
          _enterNode();
        }
      }
      if (t == Tool.pen || t == Tool.pencil) sel = -1;
    });
    if (blocked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Select a shape first to edit its nodes')));
    }
  }

  void _enterNode() {
    final n = cur;
    if (n == null) {
      pm = null;
      return;
    }
    if (n.tag != 'path' || n.hasEditTransform) {
      snap();
      n.bakeToPath();
    }
    pm = PathModel.fromD(n.attrs['d'] ?? '');
    selSp = 0;
    selAi = -1;
    ver++;
  }

  void _select(int i) => setState(() {
        sel = i;
        if (tool == Tool.node) {
          cur != null ? _enterNode() : pm = null;
        }
      });

  void _commit() {
    final m = pm;
    if (m != null) cur?.attrs['d'] = m.toD();
  }

  void _pick(Offset p) {
    for (var i = doc.nodes.length - 1; i >= 0; i--) {
      final n = doc.nodes[i];
      if (!n.visible) continue;
      final r = n.frame;
      if (r != null && r.inflate(5 / _k).contains(p)) {
        sel = i;
        return;
      }
    }
    sel = -1;
  }

  List<int>? _hitAnchor(Offset p) {
    final m = pm;
    if (m == null) return null;
    final r = 14 / _k;
    for (var s = 0; s < m.subs.length; s++) {
      for (var i = m.subs[s].a.length - 1; i >= 0; i--) {
        if ((m.subs[s].a[i].p - p).distance <= r) return [s, i];
      }
    }
    return null;
  }

  void _addPathNode(List<Anchor> a, bool closed, {bool edit = true}) {
    snap();
    final sw = (doc.viewBox.shortestSide / 100 * 3).toStringAsFixed(1);
    final model = PathModel([SubPath(a.map((e) => e.clone()).toList(), closed)]);
    final n = SvgNode(
        'path',
        {
          'd': model.toD(),
          'fill': closed ? '#9999FF' : 'none',
          'stroke': '#FFFFFF',
          'stroke-width': sw,
          'stroke-linecap': 'round',
          'stroke-linejoin': 'round',
        },
        'Path ${doc.nodes.length + 1}');
    setState(() {
      doc.nodes.add(n);
      sel = doc.nodes.length - 1;
      penA = [];
      pencilPts = [];
      if (edit) {
        tool = Tool.node;
        _enterNode();
      }
      ver++;
    });
  }

  // ── gestures ──
  void _tap(Offset p) {
    switch (tool) {
      case Tool.select:
        setState(() => _pick(p));
        break;
      case Tool.node:
        final m = pm;
        if (m != null) {
          final h = _hitAnchor(p);
          if (h != null) {
            setState(() {
              selSp = h[0];
              selAi = h[1];
            });
            return;
          }
          final s = m.hitSeg(p, 10 / _k);
          if (s != null) {
            snap();
            setState(() {
              m.splitSeg(s[0].toInt(), s[1].toInt(), s[2]);
              selSp = s[0].toInt();
              selAi = s[1].toInt() + 1;
              _commit();
              ver++;
            });
            return;
          }
        }
        final before = sel;
        setState(() {
          _pick(p);
          if (sel != before) {
            sel >= 0 ? _enterNode() : pm = null;
          } else {
            selAi = -1;
          }
        });
        break;
      case Tool.pen:
        _penPlace(p, drag: false);
        break;
      case Tool.pencil:
        break;
    }
  }

  void _penPlace(Offset p, {required bool drag}) {
    if (penA.length >= 2 && (p - penA.first.p).distance * _k < 14) {
      _addPathNode(penA, true);
      return;
    }
    setState(() => penA.add(Anchor(p)));
    _penDragging = drag;
  }

  void _panStart(Offset p) {
    _dragSnapped = false;
    _drag = 0;
    switch (tool) {
      case Tool.select:
        setState(() => _pick(p));
        break;
      case Tool.node:
        if (pm == null) return;
        final a = _selAnchor, r = 14 / _k;
        if (a != null) {
          if (a.o != null && (a.o! - p).distance <= r) {
            _drag = 3;
            return;
          }
          if (a.i != null && (a.i! - p).distance <= r) {
            _drag = 2;
            return;
          }
        }
        final h = _hitAnchor(p);
        if (h != null) {
          setState(() {
            selSp = h[0];
            selAi = h[1];
          });
          _drag = 1;
        }
        break;
      case Tool.pen:
        _penPlace(p, drag: true);
        break;
      case Tool.pencil:
        setState(() => pencilPts = [p]);
        break;
    }
  }

  /// Undo snapshot is taken on the first real movement, so taps and
  /// zero-distance drags never add empty history entries.
  void _ensureSnap() {
    if (_dragSnapped) return;
    snap();
    _dragSnapped = true;
  }

  void _panUpdate(Offset p, Offset delta) {
    switch (tool) {
      case Tool.select:
        final n = cur;
        if (n != null && delta != Offset.zero) {
          _ensureSnap();
          live(() {
            n.dx += delta.dx;
            n.dy += delta.dy;
          });
        }
        break;
      case Tool.node:
        final a = _selAnchor;
        if (_drag == 0 || a == null) return;
        _ensureSnap();
        live(() {
          if (_drag == 1) {
            a.p += delta;
            if (a.i != null) a.i = a.i! + delta;
            if (a.o != null) a.o = a.o! + delta;
          } else if (_drag == 2) {
            a.i = p;
            if (a.smooth) a.o = a.p + (a.p - p);
          } else {
            a.o = p;
            if (a.smooth) a.i = a.p + (a.p - p);
          }
          _commit();
        });
        break;
      case Tool.pen:
        if (_penDragging && penA.isNotEmpty) {
          final a = penA.last;
          setState(() {
            a.o = p;
            a.i = a.p + (a.p - p);
            a.smooth = true;
          });
        }
        break;
      case Tool.pencil:
        if (pencilPts.isNotEmpty && (p - pencilPts.last).distance * _k > 4) {
          setState(() => pencilPts.add(p));
        }
        break;
    }
  }

  void _panEnd() {
    _drag = 0;
    _dragSnapped = false;
    _penDragging = false;
    if (tool == Tool.pencil && pencilPts.isNotEmpty) _finishPencil();
  }

  /// A second finger landed: abandon the one-finger action cleanly.
  void _cancelDrag() {
    _drag = 0;
    _dragSnapped = false;
    _penDragging = false;
    if (pencilPts.isNotEmpty) setState(() => pencilPts = []);
  }

  void _finishPencil() {
    var pts = _rdp(pencilPts, 2.5 / _k);
    pencilPts = [];
    if (pts.length < 2) {
      setState(() {});
      return;
    }
    var closed = false;
    if (pts.length >= 4 && (pts.last - pts.first).distance * _k < 14) {
      closed = true;
      pts = pts.sublist(0, pts.length - 1);
    }
    final a = <Anchor>[];
    final n = pts.length;
    for (var j = 0; j < n; j++) {
      final hasPrev = closed || j > 0, hasNext = closed || j < n - 1;
      final prev = pts[closed ? (j - 1 + n) % n : math.max(j - 1, 0)];
      final next = pts[closed ? (j + 1) % n : math.min(j + 1, n - 1)];
      final t = (next - prev) / 6;
      a.add(Anchor(pts[j], i: hasPrev ? pts[j] - t : null, o: hasNext ? pts[j] + t : null, smooth: true));
    }
    _addPathNode(a, closed, edit: false);
  }

  static List<Offset> _rdp(List<Offset> p, double e) {
    if (p.length < 3) return p;
    var dmax = 0.0, idx = 0;
    for (var i = 1; i < p.length - 1; i++) {
      final d = _lineDist(p[i], p.first, p.last);
      if (d > dmax) {
        dmax = d;
        idx = i;
      }
    }
    if (dmax > e) {
      final l = _rdp(p.sublist(0, idx + 1), e), r = _rdp(p.sublist(idx), e);
      return [...l.sublist(0, l.length - 1), ...r];
    }
    return [p.first, p.last];
  }

  static double _lineDist(Offset p, Offset a, Offset b) {
    final l = (b - a).distance;
    if (l == 0) return (p - a).distance;
    return ((b.dx - a.dx) * (a.dy - p.dy) - (a.dx - p.dx) * (b.dy - a.dy)).abs() / l;
  }

  // ── node actions ──
  void _toggleSmooth() {
    final a = _selAnchor;
    if (a == null) return;
    edit(() {
      if (a.smooth) {
        a.i = a.o = null;
        a.smooth = false;
      } else {
        final s = pm!.subs[selSp];
        final n = s.a.length;
        final prev = selAi > 0 ? s.a[selAi - 1].p : (s.closed ? s.a[n - 1].p : null);
        final next = selAi < n - 1 ? s.a[selAi + 1].p : (s.closed ? s.a[0].p : null);
        final t = ((next ?? a.p) - (prev ?? a.p)) / 6;
        if (prev != null) a.i = a.p - t;
        if (next != null) a.o = a.p + t;
        a.smooth = true;
      }
      _commit();
    });
  }

  void _addNode() {
    final m = pm;
    if (m == null || selSp >= m.subs.length) return;
    final s = m.subs[selSp];
    if (selAi < 0 || selAi >= s.segCount) return;
    edit(() {
      m.splitSeg(selSp, selAi, 0.5);
      selAi++;
      _commit();
    });
  }

  void _deleteNode() {
    if (_selAnchor == null) return;
    edit(() {
      final s = pm!.subs[selSp];
      s.a.removeAt(selAi);
      if (s.a.length < 2) pm!.subs.removeAt(selSp);
      selSp = 0;
      selAi = -1;
      if (pm!.subs.isEmpty) {
        doc.nodes.removeAt(sel);
        sel = -1;
        pm = null;
        tool = Tool.select;
      } else {
        _commit();
      }
    });
  }

  void _toggleClosed() {
    final m = pm;
    if (m == null || selSp >= m.subs.length) return;
    edit(() {
      final s = m.subs[selSp];
      s.closed = !s.closed;
      _commit();
    });
  }

  void _applyCode(String code) {
    try {
      final d = SvgDoc.parse(code, allowEmpty: true);
      snap();
      setState(() {
        doc = d;
        sel = -1;
        tool = Tool.select;
        pm = null;
        ver++;
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Invalid SVG: $e')));
    }
  }

  void _fit() => setState(() {
        zoom = 0.9;
        _pan = Offset.zero;
      });

  Future<bool> _confirmDiscard() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Discard changes?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Your edits have not been added to the timeline.', style: _lbl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
        ],
      ),
    );
    return r ?? false;
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _undo.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final ok = await _confirmDiscard();
        if (ok) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: _appBar(),
        body: SafeArea(
          top: false,
          child: error != null ? _errorView() : _body(),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
        backgroundColor: _panel,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Colors.white, fontFamily: 'Ubuntu')),
          Text('Vector editor', style: _lbl.copyWith(fontSize: 10)),
        ]),
        actions: [
          IconButton(tooltip: 'Undo', onPressed: _undo.isEmpty ? null : undo, icon: Icon(Icons.undo, size: 20)),
          IconButton(tooltip: 'Redo', onPressed: _redo.isEmpty ? null : redo, icon: Icon(Icons.redo, size: 20)),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 4),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: doc.nodes.isEmpty ? null : () => Navigator.pop(context, doc.toSvg()),
              child: const Text('Add to timeline', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 10),
            const Text('Cannot open this SVG', style: _lblStrong),
            const SizedBox(height: 6),
            Text(error!, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: _lbl),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
              onPressed: () => setState(() => error = null),
              child: const Text('Start with a blank canvas'),
            ),
          ]),
        ),
      );

  Widget _body() {
    final h = MediaQuery.sizeOf(context).height;
    final panelH = (h * 0.34).clamp(190.0, 300.0).toDouble();
    return Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: _canvas()),
          Positioned(left: 8, top: 8, child: _rail()),
          Positioned(right: 8, top: 8, child: _zoomPill()),
          Positioned(left: 64, right: 12, bottom: 10, child: _bottomOverlay()),
        ]),
      ),
      _panelView(panelH),
    ]);
  }

  // ── canvas ──
  Widget _canvas() => LayoutBuilder(builder: (_, c) {
        final vb = doc.viewBox;
        final k = math.min(c.maxWidth / vb.width, c.maxHeight / vb.height) * zoom;
        _k = k;
        final w = vb.width * k, h = vb.height * k;
        _artTL = Offset((c.maxWidth - w) / 2, (c.maxHeight - h) / 2) + _pan;
        Offset toDoc(Offset l) => (l - _artTL) / k + vb.topLeft;

        final f = (tool == Tool.select) ? cur?.frame : null;
        final overlayModel = tool == Tool.pen ? PathModel([SubPath(penA, false)]) : (tool == Tool.node ? pm : null);

        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(toDoc(d.localPosition)),
            onScaleStart: (d) {
              if (d.pointerCount >= 2) {
                _pinch = true;
                _baseZoom = zoom;
                _pinchScale0 = 1;
              } else if (!_pinch) {
                _panStart(toDoc(d.localFocalPoint));
              }
            },
            onScaleUpdate: (d) {
              if (d.pointerCount >= 2) {
                if (!_pinch) {
                  _pinch = true;
                  _cancelDrag();
                  _baseZoom = zoom;
                  _pinchScale0 = d.scale;
                }
                setState(() {
                  zoom = (_baseZoom * d.scale / _pinchScale0).clamp(0.3, 6.0).toDouble();
                  _pan += d.focalPointDelta;
                });
              } else if (!_pinch) {
                _panUpdate(toDoc(d.localFocalPoint), d.focalPointDelta / k);
              }
            },
            onScaleEnd: (d) {
              if (d.pointerCount == 0) {
                if (!_pinch) _panEnd();
                _pinch = false;
              }
            },
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: Container(color: _bg)),
              Positioned(
                left: _artTL.dx,
                top: _artTL.dy,
                width: w,
                height: h,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _Checker()))),
                  Positioned.fill(child: SvgPicture.string(svg, fit: BoxFit.fill)),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.white24, width: 1))),
                    ),
                  ),
                  if (f != null)
                    Positioned.fromRect(
                      rect: Rect.fromLTWH((f.left - vb.left) * k, (f.top - vb.top) * k, f.width * k, f.height * k),
                      child: IgnorePointer(
                        child: Transform.rotate(
                          angle: cur!.rot * math.pi / 180,
                          child: Container(decoration: BoxDecoration(border: Border.all(color: _accent, width: 1.5))),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _NodePainter(
                          pm: overlayModel,
                          sp: tool == Tool.pen ? 0 : selSp,
                          ai: tool == Tool.pen ? penA.length - 1 : selAi,
                          k: k,
                          origin: vb.topLeft,
                          pencil: pencilPts,
                          pen: tool == Tool.pen,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        );
      });

  // ── floating controls ──
  BoxDecoration get _floatDeco => BoxDecoration(
        color: _panel.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      );

  Widget _rail() {
    Widget b(Tool t, IconData i, String l) {
      final on = tool == t;
      return Tooltip(
        message: l,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _setTool(t),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: on ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(i, size: 19, color: on ? Colors.black : Colors.white70),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: _floatDeco,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        b(Tool.select, Icons.near_me_outlined, 'Select'),
        b(Tool.node, Icons.timeline, 'Nodes'),
        b(Tool.pen, Icons.create_outlined, 'Pen'),
        b(Tool.pencil, Icons.draw_outlined, 'Pencil'),
      ]),
    );
  }

  Widget _zoomPill() {
    Widget ib(IconData i, String t, VoidCallback f) => IconButton(
          tooltip: t,
          onPressed: f,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(i, size: 17, color: Colors.white70),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: _floatDeco,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ib(Icons.remove, 'Zoom out', () => setState(() => zoom = (zoom / 1.25).clamp(0.3, 6.0).toDouble())),
        GestureDetector(
          onTap: _fit,
          child: SizedBox(width: 44, child: Text('${(zoom * 100).round()}%', textAlign: TextAlign.center, style: _lbl)),
        ),
        ib(Icons.add, 'Zoom in', () => setState(() => zoom = (zoom * 1.25).clamp(0.3, 6.0).toDouble())),
        ib(Icons.fit_screen_outlined, 'Fit', _fit),
      ]),
    );
  }

  Widget _bottomOverlay() {
    const hints = {
      Tool.select: 'Tap to select · drag to move · pinch to zoom',
      Tool.node: 'Drag nodes and handles · tap a segment to add a node',
      Tool.pen: 'Tap for corners · drag for curves · tap first node to close',
      Tool.pencil: 'Draw freehand — it becomes an editable path',
    };
    final bar = _contextBar();
    return IgnorePointer(
      ignoring: bar == null,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (bar != null) bar,
        if (bar != null) const SizedBox(height: 8),
        IgnorePointer(
          child: Text(hints[tool]!, textAlign: TextAlign.center, maxLines: 2, style: _lbl.copyWith(color: Colors.white38, fontSize: 10.5)),
        ),
      ]),
    );
  }

  Widget? _contextBar() {
    Widget act(IconData i, String l, VoidCallback? f) => TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white24,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: f,
          icon: Icon(i, size: 15),
          label: Text(l, style: const TextStyle(fontSize: 11)),
        );

    List<Widget>? items;
    if (tool == Tool.node && pm != null) {
      final a = _selAnchor;
      final closed = selSp < pm!.subs.length ? pm!.subs[selSp].closed : false;
      items = [
        act(a?.smooth == true ? Icons.change_history : Icons.rounded_corner, a?.smooth == true ? 'Corner' : 'Smooth', a == null ? null : _toggleSmooth),
        act(Icons.add, 'Add node', a == null ? null : _addNode),
        act(Icons.remove, 'Delete', a == null ? null : _deleteNode),
        act(closed ? Icons.call_split : Icons.loop, closed ? 'Open' : 'Close', _toggleClosed),
      ];
    } else if (tool == Tool.pen && penA.isNotEmpty) {
      items = [
        act(Icons.check, 'Done', penA.length < 2 ? null : () => _addPathNode(penA, false)),
        act(Icons.loop, 'Close', penA.length < 3 ? null : () => _addPathNode(penA, true)),
        act(Icons.backspace_outlined, 'Undo point', () => setState(() => penA.removeLast())),
        act(Icons.close, 'Cancel', () => setState(() => penA = [])),
      ];
    }
    if (items == null) return null;
    return Container(
      decoration: _floatDeco.copyWith(borderRadius: BorderRadius.circular(22)),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: items)),
    );
  }

  // ── bottom panel ──
  Widget _panelView(double bodyH) {
    Widget tab(IconData i, String t) => Tab(
          height: 38,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 15),
            const SizedBox(width: 6),
            Text(t),
          ]),
        );
    return Container(
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: TabBar(
              controller: tabs,
              indicatorColor: _accent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              onTap: (i) {
                setState(() => _panelOpen = (i == _lastTab) ? !_panelOpen : true);
                _lastTab = i;
              },
              tabs: [
                tab(Icons.tune, 'Properties'),
                tab(Icons.layers_outlined, 'Layers'),
                tab(Icons.code, 'Code'),
              ],
            ),
          ),
          IconButton(
            tooltip: _panelOpen ? 'Collapse panel' : 'Expand panel',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _panelOpen = !_panelOpen),
            icon: Icon(_panelOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 20, color: Colors.white70),
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: _panelOpen ? bodyH : 0,
            child: _panelOpen
                ? TabBarView(controller: tabs, children: [
                    _props(),
                    _layers(),
                    _CodeTab(key: ValueKey(ver), source: svg, onApply: _applyCode),
                  ])
                : null,
          ),
        ),
      ]),
    );
  }

  // ── properties ──
  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(t.toUpperCase(), style: _lbl.copyWith(fontSize: 10, letterSpacing: 1, color: Colors.white38)),
      );

  Widget _props() {
    final n = cur;
    if (n == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.touch_app_outlined, color: Colors.white24, size: 28),
            SizedBox(height: 8),
            Text('Select a layer to edit it,\nor draw with Pen / Pencil', textAlign: TextAlign.center, style: _lbl),
          ]),
        ),
      );
    }
    final sMax = math.max(10.0, doc.viewBox.shortestSide / 8);
    final off = doc.viewBox.shortestSide / 50;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 16), children: [
      Row(children: [
        Expanded(child: Text(n.name, overflow: TextOverflow.ellipsis, style: _lblStrong)),
        Text(n.tag, style: _lbl),
      ]),
      _section('Appearance'),
      _colorRow('Fill', n.attrs['fill'] ?? '#000000', (v) => edit(() => n.attrs['fill'] = v)),
      _colorRow('Stroke', n.attrs['stroke'] ?? 'none', (v) => edit(() => n.attrs['stroke'] = v)),
      _sl('Stroke width', double.tryParse(n.attrs['stroke-width'] ?? '') ?? 1, 0, sMax, (v) => live(() => n.attrs['stroke-width'] = v.toStringAsFixed(1))),
      _sl('Opacity', double.tryParse(n.attrs['opacity'] ?? '') ?? 1, 0, 1, (v) => live(() => n.attrs['opacity'] = v.toStringAsFixed(2)),
          fmt: (v) => '${(v * 100).round()}%'),
      _section('Transform'),
      _sl('Rotation', n.rot, -180, 180, (v) => live(() => n.rot = v), fmt: (v) => '${v.round()}°'),
      _sl('Scale', n.scale, 0.1, 4, (v) => live(() => n.scale = v), fmt: (v) => '${(v * 100).round()}%'),
      _section('Arrange'),
      Wrap(spacing: 8, runSpacing: 6, children: [
        _act(Icons.copy, 'Duplicate', () => edit(() {
              doc.nodes.add(n.clone()
                ..dx += off
                ..dy += off
                ..name = '${n.name} copy');
              sel = doc.nodes.length - 1;
            })),
        _act(Icons.flip_to_front, 'Forward', sel < doc.nodes.length - 1 ? () {
          edit(() {
            doc.nodes.insert(sel + 1, doc.nodes.removeAt(sel));
            sel++;
          });
        } : null),
        _act(Icons.flip_to_back, 'Backward', sel > 0 ? () {
          edit(() {
            doc.nodes.insert(sel - 1, doc.nodes.removeAt(sel));
            sel--;
          });
        } : null),
        _act(Icons.delete_outline, 'Delete', () => edit(() {
              doc.nodes.removeAt(sel);
              sel = -1;
              pm = null;
              if (tool == Tool.node) tool = Tool.select;
            }), danger: true),
      ]),
    ]);
  }

  Widget _act(IconData i, String t, VoidCallback? f, {bool danger = false}) => OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? Colors.redAccent : Colors.white70,
        side: BorderSide(color: danger ? Colors.redAccent.withValues(alpha: .5) : Colors.white24),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: f,
      icon: Icon(i, size: 15),
      label: Text(t, style: const TextStyle(fontSize: 11)));

  Widget _sl(String l, double v, double mn, double mx, ValueChanged<double> on, {String Function(double)? fmt}) => SizedBox(
        height: 32,
        child: Row(children: [
          SizedBox(width: 84, child: Text(l, style: _lbl)),
          Expanded(
              child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: _accent,
                thumbColor: _accent,
                inactiveTrackColor: Colors.white12,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay),
            child: Slider(value: v.clamp(mn, mx).toDouble(), min: mn, max: mx, onChangeStart: (_) => snap(), onChanged: on),
          )),
          SizedBox(width: 44, child: Text(fmt?.call(v) ?? v.toStringAsFixed(1), textAlign: TextAlign.end, style: _lbl)),
        ]),
      );

  Color? _parse(String s) {
    s = s.trim();
    if (!s.startsWith('#')) return null;
    var h = s.substring(1);
    if (h.length == 3) h = h.split('').map((c) => c + c).join();
    final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
    return v == null ? null : Color(0xFF000000 | v);
  }

  String _hex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Widget _colorRow(String label, String value, ValueChanged<String> on) {
    final c = _parse(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 84, child: Text(label, style: _lbl)),
        Expanded(
          child: SizedBox(
            height: 26,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              GestureDetector(
                onTap: () => on('none'),
                child: Container(
                    width: 22,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(border: Border.all(color: value == 'none' ? _accent : Colors.white24, width: 1.5), borderRadius: BorderRadius.circular(4)),
                    child: Icon(Icons.block, size: 14, color: Colors.redAccent)),
              ),
              for (final s in _swatches)
                GestureDetector(
                  onTap: () => on(_hex(s)),
                  child: Container(
                    width: 22,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: Color(s), borderRadius: BorderRadius.circular(4), border: Border.all(color: c?.toARGB32() == s ? _accent : Colors.white24, width: 1.5)),
                  ),
                ),
            ]),
          ),
        ),
        Container(
          width: 76,
          height: 26,
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: _panelHi, borderRadius: BorderRadius.circular(6)),
          child: TextFormField(
            key: ValueKey('$label$sel$value'),
            initialValue: value,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.only(top: 6)),
            onFieldSubmitted: (t) {
              final v = t.trim();
              if (_parse(v) != null || v == 'none') on(v);
            },
          ),
        ),
      ]),
    );
  }

  // ── layers ──
  Widget _layers() {
    final n = doc.nodes.length;
    if (n == 0) {
      return const Center(child: Text('No layers yet', style: _lbl));
    }
    return ReorderableListView.builder(
      itemCount: n,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 8),
      // ignore: deprecated_member_use
      onReorder: (o, nw) {
        if (nw > o) nw--;
        edit(() {
          final item = doc.nodes.removeAt(n - 1 - o);
          doc.nodes.insert(n - 1 - nw, item);
          sel = n - 1 - nw;
          _syncPm();
        });
      },
      itemBuilder: (_, i) {
        final idx = n - 1 - i;
        final node = doc.nodes[idx];
        final fill = _parse(node.attrs['fill'] ?? '#000000') ?? _parse(node.attrs['stroke'] ?? '') ?? Colors.white24;
        final on = idx == sel;
        return Material(
          key: ObjectKey(node),
          color: on ? _accent.withValues(alpha: .16) : Colors.transparent,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            onTap: () => _select(idx),
            leading: InkWell(
              onTap: () => edit(() => node.visible = !node.visible),
              child: Icon(node.visible ? Icons.visibility : Icons.visibility_off, size: 17, color: Colors.white54),
            ),
            title: Row(children: [
              Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white24, width: .5))),
              const SizedBox(width: 8),
              Expanded(child: Text(node.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12))),
            ]),
            subtitle: Text(node.tag, style: _lbl.copyWith(fontSize: 10)),
            trailing: ReorderableDragStartListener(
              index: i,
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle, size: 18, color: Colors.white38)),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────── overlay: nodes, handles, pen preview ─────────────────

class _NodePainter extends CustomPainter {
  _NodePainter({required this.pm, required this.sp, required this.ai, required this.k, required this.origin, required this.pencil, required this.pen});
  final PathModel? pm;
  final int sp, ai;
  final double k;
  final Offset origin;
  final List<Offset> pencil;
  final bool pen;

  Offset t(Offset o) => (o - origin) * k;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _accent;
    final m = pm;
    if (m != null) {
      canvas.drawPath(m.toPath(t), line);
      for (var si = 0; si < m.subs.length; si++) {
        final s = m.subs[si];
        for (var j = 0; j < s.a.length; j++) {
          final a = s.a[j];
          final selected = si == sp && j == ai;
          final c = t(a.p);
          if (selected) {
            for (final h in [a.i, a.o]) {
              if (h == null) continue;
              canvas.drawLine(c, t(h), Paint()..color = Colors.white54..strokeWidth = 1);
              canvas.drawCircle(t(h), 5, Paint()..color = Colors.white);
              canvas.drawCircle(t(h), 5, line);
            }
          }
          final r = Rect.fromCenter(center: c, width: 10, height: 10);
          canvas.drawRect(r, Paint()..color = selected ? _accent : Colors.white);
          canvas.drawRect(r, line);
          if (pen && j == 0 && s.a.length >= 2) canvas.drawCircle(c, 10, line);
        }
      }
    }
    if (pencil.length > 1) {
      final p = Path()..moveTo(t(pencil.first).dx, t(pencil.first).dy);
      for (final o in pencil.skip(1)) {
        p.lineTo(t(o).dx, t(o).dy);
      }
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _CodeTab extends StatefulWidget {
  const _CodeTab({super.key, required this.source, required this.onApply});
  final String source;
  final ValueChanged<String> onApply;
  @override
  State<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends State<_CodeTab> {
  late final c = TextEditingController(text: widget.source);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(children: [
          Expanded(
            child: TextField(
              controller: c,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(color: Color(0xFFCFCFFF), fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                filled: true,
                fillColor: _bg,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
              onPressed: () => c.text = widget.source,
              icon: Icon(Icons.restart_alt, size: 16),
              label: const Text('Reset'),
            ),
            TextButton.icon(
              onPressed: () => widget.onApply(c.text),
              icon: Icon(Icons.check, size: 16),
              label: const Text('Apply code'),
            ),
          ]),
        ]),
      );
}

class _Checker extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    const t = 10.0;
    final a = Paint()..color = const Color(0xFF2E2E2E), b = Paint()..color = const Color(0xFF383838);
    for (var y = 0.0; y < s.height; y += t) {
      for (var x = 0.0; x < s.width; x += t) {
        canvas.drawRect(Rect.fromLTWH(x, y, t, t), ((x ~/ t + y ~/ t) % 2 == 0) ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}