import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:flutter_video_editor/core/models/svg_model.dart';

const _accent = Color(0xFF9999FF);
const _panel = Color(0xFF232323);
const _bg = Color(0xFF181818);
const _lbl = TextStyle(color: Color(0xFFB4B4B4), fontSize: 11, fontFamily: 'Poppins');

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
  double zoom = 0.9, _k = 1;
  late final TabController tabs = TabController(length: 3, vsync: this);
  String? error;

  Tool tool = Tool.select;
  PathModel? pm; // path being node-edited
  int selSp = 0, selAi = -1; // selected subpath / anchor
  int _drag = 0; // 0 none, 1 anchor, 2 in-handle, 3 out-handle
  List<Anchor> penA = [];
  bool _penDragging = false;
  List<Offset> pencilPts = [];

  static const _swatches = [0xFFFFFFFF, 0xFF000000, 0xFF9999FF, 0xFF2D8CFF, 0xFF00C2A8, 0xFFFFC107, 0xFFFF7043, 0xFFEF5350, 0xFFE040FB];

  SvgNode? get cur => (sel >= 0 && sel < doc.nodes.length) ? doc.nodes[sel] : null;
  Anchor? get _selAnchor {
    final p = pm;
    if (p == null || selSp >= p.subs.length || selAi < 0 || selAi >= p.subs[selSp].a.length) return null;
    return p.subs[selSp].a[selAi];
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
    if (pm == null || selSp >= pm!.subs.length || selAi >= pm!.subs[selSp].a.length) selAi = -1;
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a shape first to edit its nodes')));
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

  void _commit() => cur?.attrs['d'] = pm!.toD();

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
    switch (tool) {
      case Tool.select:
        setState(() => _pick(p));
        if (cur != null) snap();
        break;
      case Tool.node:
        if (pm == null) return;
        final a = _selAnchor, r = 14 / _k;
        if (a != null) {
          if (a.o != null && (a.o! - p).distance <= r) {
            _drag = 3;
            snap();
            return;
          }
          if (a.i != null && (a.i! - p).distance <= r) {
            _drag = 2;
            snap();
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
          snap();
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

  void _panUpdate(Offset p, Offset delta) {
    switch (tool) {
      case Tool.select:
        final n = cur;
        if (n != null) {
          live(() {
            n.dx += delta.dx;
            n.dy += delta.dy;
          });
        }
        break;
      case Tool.node:
        final a = _selAnchor;
        if (_drag == 0 || a == null) return;
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
        if (pencilPts.isNotEmpty && (p - pencilPts.last).distance * _k > 4) setState(() => pencilPts.add(p));
        break;
    }
  }

  void _panEnd() {
    _drag = 0;
    _penDragging = false;
    if (tool == Tool.pencil && pencilPts.isNotEmpty) _finishPencil();
  }

  void _finishPencil() {
    final pts = _rdp(pencilPts, 2.5 / _k);
    pencilPts = [];
    if (pts.length < 2) {
      setState(() {});
      return;
    }
    final a = <Anchor>[];
    for (var j = 0; j < pts.length; j++) {
      final prev = pts[math.max(j - 1, 0)], next = pts[math.min(j + 1, pts.length - 1)];
      final t = (next - prev) / 6;
      a.add(Anchor(pts[j], i: j > 0 ? pts[j] - t : null, o: j < pts.length - 1 ? pts[j] + t : null, smooth: true));
    }
    _addPathNode(a, false, edit: false);
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
    final s = pm!.subs[selSp];
    if (selAi < 0 || selAi >= s.segCount) return;
    edit(() {
      pm!.splitSeg(selSp, selAi, 0.5);
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
    if (pm == null || selSp >= pm!.subs.length) return;
    edit(() {
      final s = pm!.subs[selSp];
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid SVG: $e')));
    }
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _panel,
        elevation: 0,
        title: Text('Essential Graphics  ·  ${widget.title}',
            style: const TextStyle(fontSize: 13, color: Colors.white70, fontFamily: 'Poppins')),
        actions: [
          IconButton(onPressed: _undo.isEmpty ? null : undo, icon: const Icon(Icons.undo, size: 20)),
          IconButton(onPressed: _redo.isEmpty ? null : redo, icon: const Icon(Icons.redo, size: 20)),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 4),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
              onPressed: doc.nodes.isEmpty ? null : () => Navigator.pop(context, doc.toSvg()),
              child: const Text('Add to timeline', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text('Cannot open SVG\n$error', style: const TextStyle(color: Colors.redAccent)))
          : Column(children: [
              Expanded(child: Stack(children: [Positioned.fill(child: _canvas()), _hint()])),
              _toolbar(),
              _zoomBar(),
              Container(
                height: 250,
                color: _panel,
                child: Column(children: [
                  TabBar(
                    controller: tabs,
                    indicatorColor: _accent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    tabs: const [Tab(text: 'Properties', height: 36), Tab(text: 'Layers', height: 36), Tab(text: 'Code', height: 36)],
                  ),
                  Expanded(
                      child: TabBarView(controller: tabs, children: [
                    _props(),
                    _layers(),
                    _CodeTab(key: ValueKey(ver), source: doc.toSvg(), onApply: _applyCode),
                  ])),
                ]),
              ),
            ]),
    );
  }

  Widget _hint() {
    const hints = {
      Tool.select: 'Tap to select · drag to move',
      Tool.node: 'Drag nodes and handles · tap a segment to add a node',
      Tool.pen: 'Tap for corners · drag for curves · tap first node to close',
      Tool.pencil: 'Draw freehand — it becomes a smooth, editable path',
    };
    return Positioned(
        left: 10,
        top: 6,
        child: IgnorePointer(child: Text(hints[tool]!, style: _lbl.copyWith(color: Colors.white38))));
  }

  Widget _canvas() => LayoutBuilder(builder: (_, c) {
        final vb = doc.viewBox;
        final k = math.min(c.maxWidth / vb.width, c.maxHeight / vb.height) * zoom;
        _k = k;
        final w = vb.width * k, h = vb.height * k;
        final f = (tool == Tool.select) ? cur?.frame : null;
        final overlayModel = tool == Tool.pen ? PathModel([SubPath(penA)]) : (tool == Tool.node ? pm : null);
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: (d) => _tap(d.localPosition / k + vb.topLeft),
              onPanStart: (d) => _panStart(d.localPosition / k + vb.topLeft),
              onPanUpdate: (d) => _panUpdate(d.localPosition / k + vb.topLeft, d.delta / k),
              onPanEnd: (_) => _panEnd(),
              onPanCancel: _panEnd,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: CustomPaint(painter: _Checker())),
                Positioned.fill(child: SvgPicture.string(doc.toSvg(), fit: BoxFit.fill)),
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
          ),
        );
      });

  Widget _toolbar() {
    Widget tb(Tool t, IconData i, String l) {
      final on = tool == t;
      return InkWell(
        onTap: () => _setTool(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? _accent : Colors.transparent, width: 2))),
          child: Row(children: [
            Icon(i, size: 17, color: on ? _accent : Colors.white70),
            const SizedBox(width: 5),
            Text(l, style: TextStyle(fontSize: 11, color: on ? Colors.white : Colors.white54)),
          ]),
        ),
      );
    }

    Widget mini(IconData i, String l, VoidCallback? f) => TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
        onPressed: f,
        icon: Icon(i, size: 15),
        label: Text(l, style: const TextStyle(fontSize: 11)));

    final a = _selAnchor;
    final closed = (pm != null && selSp < pm!.subs.length) ? pm!.subs[selSp].closed : false;
    return Container(
      color: const Color(0xFF1E1E1E),
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        tb(Tool.select, Icons.near_me_outlined, 'Select'),
        tb(Tool.node, Icons.timeline, 'Nodes'),
        tb(Tool.pen, Icons.create_outlined, 'Pen'),
        tb(Tool.pencil, Icons.draw_outlined, 'Pencil'),
        const VerticalDivider(color: Colors.white12, width: 16, indent: 8, endIndent: 8),
        if (tool == Tool.node && pm != null) ...[
          mini(a?.smooth == true ? Icons.change_history : Icons.rounded_corner, a?.smooth == true ? 'Corner' : 'Smooth', a == null ? null : _toggleSmooth),
          mini(Icons.add, 'Add node', a == null ? null : _addNode),
          mini(Icons.remove, 'Delete node', a == null ? null : _deleteNode),
          mini(closed ? Icons.call_split : Icons.loop, closed ? 'Open path' : 'Close path', _toggleClosed),
        ],
        if (tool == Tool.pen) ...[
          mini(Icons.check, 'Done', penA.length < 2 ? null : () => _addPathNode(penA, false)),
          mini(Icons.loop, 'Close', penA.length < 3 ? null : () => _addPathNode(penA, true)),
          mini(Icons.close, 'Cancel', penA.isEmpty ? null : () => setState(() => penA = [])),
        ],
      ]),
    );
  }

  Widget _zoomBar() => Container(
        color: _panel,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 32,
        child: Row(children: [
          const Icon(Icons.zoom_out, size: 16, color: Colors.white54),
          Expanded(child: Slider(value: zoom, min: 0.3, max: 2.5, activeColor: _accent, onChanged: (v) => setState(() => zoom = v))),
          const Icon(Icons.zoom_in, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text('${(zoom * 100).round()}%', style: _lbl),
        ]),
      );

  // ── properties ──
  Widget _props() {
    final n = cur;
    if (n == null) return const Center(child: Text('Select a layer, or draw with Pen / Pencil', style: _lbl));
    return ListView(padding: const EdgeInsets.all(14), children: [
      _colorRow('Fill', n.attrs['fill'] ?? '#000000', (v) => edit(() => n.attrs['fill'] = v)),
      _colorRow('Stroke', n.attrs['stroke'] ?? 'none', (v) => edit(() => n.attrs['stroke'] = v)),
      _sl('Stroke width', double.tryParse(n.attrs['stroke-width'] ?? '') ?? 1, 0, 30, (v) => live(() => n.attrs['stroke-width'] = v.toStringAsFixed(1))),
      _sl('Opacity', double.tryParse(n.attrs['opacity'] ?? '') ?? 1, 0, 1, (v) => live(() => n.attrs['opacity'] = v.toStringAsFixed(2)),
          fmt: (v) => '${(v * 100).round()}%'),
      const Divider(color: Colors.white12, height: 20),
      _sl('Rotation', n.rot, -180, 180, (v) => live(() => n.rot = v), fmt: (v) => '${v.round()}°'),
      _sl('Scale', n.scale, 0.1, 4, (v) => live(() => n.scale = v), fmt: (v) => '${(v * 100).round()}%'),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        _act(Icons.copy, 'Duplicate', () => edit(() {
              doc.nodes.add(n.clone()
                ..dx += 6
                ..dy += 6
                ..name = '${n.name} copy');
              sel = doc.nodes.length - 1;
            })),
        _act(Icons.flip_to_front, 'Forward', () {
          if (sel < doc.nodes.length - 1) {
            edit(() {
              doc.nodes.insert(sel + 1, doc.nodes.removeAt(sel));
              sel++;
            });
          }
        }),
        _act(Icons.flip_to_back, 'Backward', () {
          if (sel > 0) {
            edit(() {
              doc.nodes.insert(sel - 1, doc.nodes.removeAt(sel));
              sel--;
            });
          }
        }),
        _act(Icons.delete_outline, 'Delete', () => edit(() {
              doc.nodes.removeAt(sel);
              sel = -1;
              pm = null;
              if (tool == Tool.node) tool = Tool.select;
            })),
      ]),
    ]);
  }

  Widget _act(IconData i, String t, VoidCallback f) => OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24), visualDensity: VisualDensity.compact),
      onPressed: f,
      icon: Icon(i, size: 15),
      label: Text(t, style: const TextStyle(fontSize: 11)));

  Widget _sl(String l, double v, double mn, double mx, ValueChanged<double> on, {String Function(double)? fmt}) => Row(children: [
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
          child: Slider(value: v.clamp(mn, mx), min: mn, max: mx, onChangeStart: (_) => snap(), onChanged: on),
        )),
        SizedBox(width: 44, child: Text(fmt?.call(v) ?? v.toStringAsFixed(1), textAlign: TextAlign.end, style: _lbl)),
      ]);

  Color? _parse(String s) {
    s = s.trim();
    if (!s.startsWith('#')) return null;
    var h = s.substring(1);
    if (h.length == 3) h = h.split('').map((c) => c + c).join();
    final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
    return v == null ? null : Color(0xFF000000 | v);
  }

  String _hex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

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
                    child: const Icon(Icons.block, size: 14, color: Colors.redAccent)),
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
        SizedBox(
          width: 74,
          child: TextFormField(
            key: ValueKey('$label$sel$value'),
            initialValue: value,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            onFieldSubmitted: (t) {
              if (_parse(t) != null || t == 'none') on(t);
            },
          ),
        ),
      ]),
    );
  }

  // ── layers ──
  Widget _layers() {
    final n = doc.nodes.length;
    return ReorderableListView.builder(
      itemCount: n,
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
        return Container(
          key: ValueKey('${node.hashCode}$idx'),
          color: idx == sel ? _accent.withValues(alpha: .18) : Colors.transparent,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            onTap: () => _select(idx),
            leading: InkWell(
              onTap: () => edit(() => node.visible = !node.visible),
              child: Icon(node.visible ? Icons.visibility : Icons.visibility_off, size: 17, color: Colors.white54),
            ),
            title: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(node.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12))),
            ]),
            subtitle: Text(node.tag, style: _lbl.copyWith(fontSize: 10)),
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
              canvas.drawCircle(t(h), 4.5, Paint()..color = Colors.white);
              canvas.drawCircle(t(h), 4.5, line);
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Expanded(
            child: TextField(
              controller: c,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: Color(0xFFCFCFFF), fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(filled: true, fillColor: _bg, border: InputBorder.none),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: () => widget.onApply(c.text), icon: const Icon(Icons.check, size: 16), label: const Text('Apply code')),
          ),
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