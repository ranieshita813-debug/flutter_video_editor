import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:path_parsing/path_parsing.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:xml/xml.dart';

// ───────────────────────── SVG DOCUMENT MODEL ─────────────────────────

class SvgNode {
  SvgNode(this.tag, this.attrs, this.name);
  String tag;
  final Map<String, String> attrs;
  String name;
  bool visible = true;
  double dx = 0, dy = 0, rot = 0, scale = 1;

  SvgNode clone() => SvgNode(tag, Map.of(attrs), name)
    ..visible = visible
    ..dx = dx
    ..dy = dy
    ..rot = rot
    ..scale = scale;

  double _n(String k, [double d = 0]) =>
      double.tryParse((attrs[k] ?? '').replaceAll(RegExp(r'[a-zA-Z%]'), '')) ?? d;

  /// Local bounds before the editor transform.
  Rect? get box {
    switch (tag) {
      case 'rect':
        return Rect.fromLTWH(_n('x'), _n('y'), _n('width'), _n('height'));
      case 'circle':
        return Rect.fromCircle(center: Offset(_n('cx'), _n('cy')), radius: _n('r'));
      case 'ellipse':
        return Rect.fromCenter(
            center: Offset(_n('cx'), _n('cy')), width: _n('rx') * 2, height: _n('ry') * 2);
      case 'line':
        return Rect.fromPoints(Offset(_n('x1'), _n('y1')), Offset(_n('x2'), _n('y2')));
      case 'polygon':
      case 'polyline':
        final v = (attrs['points'] ?? '')
            .split(RegExp(r'[\s,]+'))
            .where((e) => e.isNotEmpty)
            .map(double.tryParse)
            .whereType<double>()
            .toList();
        if (v.length < 4) return null;
        final pts = [for (var i = 0; i + 1 < v.length; i += 2) Offset(v[i], v[i + 1])];
        return pts.skip(1).fold<Rect>(
            Rect.fromPoints(pts.first, pts.first), (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
      case 'path':
        try {
          return parseSvgPathData(attrs['d'] ?? '').getBounds();
        } catch (_) {
          return null;
        }
    }
    return null;
  }

  /// Bounds after translate/scale (rotation is drawn on the overlay).
  Rect? get frame {
    final b = box;
    if (b == null) return null;
    return Rect.fromCenter(
        center: b.center + Offset(dx, dy), width: b.width * scale, height: b.height * scale);
  }

  String toXml() {
    final a = attrs.entries.map((e) => '${e.key}="${_esc(e.value)}"').join(' ');
    final c = box?.center ?? Offset.zero;
    final t = 'translate($dx $dy) translate(${c.dx} ${c.dy}) rotate($rot) '
        'scale($scale) translate(${-c.dx} ${-c.dy})';
    return '<g transform="$t"><$tag $a/></g>';
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
}

class SvgDoc {
  SvgDoc(this.viewBox, this.defs, this.nodes);
  Rect viewBox;
  String defs;
  List<SvgNode> nodes;

  static const _shapes = {'path', 'rect', 'circle', 'ellipse', 'line', 'polygon', 'polyline'};
  static const _skip = {'defs', 'clipPath', 'mask', 'symbol', 'marker', 'pattern'};
  static const _inherit = {'fill', 'stroke', 'stroke-width', 'fill-rule', 'opacity'};

  SvgDoc clone() => SvgDoc(viewBox, defs, nodes.map((e) => e.clone()).toList());

  factory SvgDoc.parse(String src, {bool allowEmpty = false}) {
    final root = XmlDocument.parse(src).rootElement;
    if (root.name.local != 'svg') throw const FormatException('Not an SVG file');
    double? num(String? s) => double.tryParse((s ?? '').replaceAll(RegExp(r'[a-zA-Z%]'), ''));
    final v = root.getAttribute('viewBox')?.trim().split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
    final vb = (v != null && v.length == 4 && !v.contains(null))
        ? Rect.fromLTWH(v[0]!, v[1]!, v[2]!, v[3]!)
        : Rect.fromLTWH(0, 0, num(root.getAttribute('width')) ?? 100, num(root.getAttribute('height')) ?? 100);
    final defs = root.childElements.where((e) => e.name.local == 'defs').map((e) => e.toXmlString()).join();

    final nodes = <SvgNode>[];
    for (final e in root.descendantElements) {
      if (!_shapes.contains(e.name.local)) {
        continue;
      }
      final anc = e.ancestorElements.where((a) => a != root).toList().reversed.toList(); // outer first
      if (anc.any((a) => _skip.contains(a.name.local))) {
        continue;
      }
      final attrs = <String, String>{};
      final transforms = <String>[];
      void read(XmlElement x, bool all) {
        for (final at in x.attributes) {
          final k = at.name.local;
          if (k == 'transform') {
            transforms.add(at.value);
          } else if (k != 'style' && k != 'class' && (all || _inherit.contains(k))) {
            attrs[k] = at.value;
          }
        }
        for (final decl in (x.getAttribute('style') ?? '').split(';')) {
          final p = decl.split(':');
          if (p.length == 2 && (all || _inherit.contains(p[0].trim()))) {
            attrs[p[0].trim()] = p[1].trim();
          }
        }
      }

      for (final a in anc) {
        read(a, false);
      }
      read(e, true);
      if (transforms.isNotEmpty) attrs['transform'] = transforms.join(' ');
      nodes.add(SvgNode(e.name.local, attrs, attrs['id'] ?? '${e.name.local} ${nodes.length + 1}'));
    }
    if (nodes.isEmpty && !allowEmpty) throw const FormatException('No editable shapes found');
    return SvgDoc(vb, defs, nodes);
  }

  String toSvg() {
    final b = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="${viewBox.left} ${viewBox.top} ${viewBox.width} ${viewBox.height}">')
      ..write(defs);
    for (final n in nodes.where((n) => n.visible)) {
      b.write(n.toXml());
    }
    return (b..write('</svg>')).toString();
  }
}


// ───────────────────────── PATH MODEL (editable anchors) ─────────────────────────

/// One node of a path. [i] / [o] are the absolute positions of the in / out
/// bezier handles (null = no handle, i.e. a sharp corner on that side).
class Anchor {
  Anchor(this.p, {this.i, this.o, this.smooth = false});
  Offset p;
  Offset? i, o;
  bool smooth;
  Anchor clone() => Anchor(p, i: i, o: o, smooth: smooth);
}

class SubPath {
  SubPath(this.a, [this.closed = false]);
  List<Anchor> a;
  bool closed;
  int get segCount => closed ? a.length : math.max(0, a.length - 1);
}

class _Proxy extends PathProxy {
  final subs = <SubPath>[];
  SubPath? _cur;
  SubPath _sp() {
    if (_cur == null) {
      _cur = SubPath([]);
      subs.add(_cur!);
    }
    return _cur!;
  }

  @override
  void moveTo(double x, double y) {
    _cur = SubPath([Anchor(Offset(x, y))]);
    subs.add(_cur!);
  }

  @override
  void lineTo(double x, double y) => _sp().a.add(Anchor(Offset(x, y)));

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    final s = _sp();
    if (s.a.isEmpty) s.a.add(Anchor(Offset(x1, y1)));
    s.a.last.o = Offset(x1, y1);
    s.a.add(Anchor(Offset(x3, y3), i: Offset(x2, y2)));
  }

  @override
  void close() {
    final s = _cur;
    if (s == null) return;
    s.closed = true;
    if (s.a.length > 1 && (s.a.last.p - s.a.first.p).distance < 1e-6) {
      final l = s.a.removeLast();
      s.a.first.i = l.i;
    }
    _cur = null;
  }
}

Offset _bez(Anchor p, Anchor q, double t) {
  if (p.o == null && q.i == null) return Offset.lerp(p.p, q.p, t)!;
  final b = p.o ?? p.p, c = q.i ?? q.p, u = 1 - t;
  return p.p * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + q.p * (t * t * t);
}

class PathModel {
  PathModel(this.subs);
  List<SubPath> subs;

  factory PathModel.fromD(String d) {
    final px = _Proxy();
    try {
      writeSvgPathDataToPath(d, px);
    } catch (_) {}
    final subs = px.subs.where((s) => s.a.isNotEmpty).toList();
    for (final s in subs) {
      for (final a in s.a) {
        a.smooth = _collinear(a);
      }
    }
    return PathModel(subs);
  }

  static bool _collinear(Anchor a) {
    if (a.i == null || a.o == null) return false;
    final u = a.p - a.i!, v = a.o! - a.p;
    final l = u.distance * v.distance;
    if (l < 1e-6) return false;
    return (u.dx * v.dy - u.dy * v.dx).abs() / l < 0.02 && (u.dx * v.dx + u.dy * v.dy) > 0;
  }

  void transform(Matrix4 m) {
    Offset t(Offset o) => MatrixUtils.transformPoint(m, o);
    for (final s in subs) {
      for (final a in s.a) {
        a.p = t(a.p);
        if (a.i != null) a.i = t(a.i!);
        if (a.o != null) a.o = t(a.o!);
      }
    }
  }

  String toD() {
    final b = StringBuffer();
    String pt(Offset o) => '${o.dx.toStringAsFixed(2)} ${o.dy.toStringAsFixed(2)}';
    for (final s in subs) {
      if (s.a.isEmpty) continue;
      b.write('M ${pt(s.a[0].p)} ');
      for (var k = 0; k < s.segCount; k++) {
        final p = s.a[k], q = s.a[(k + 1) % s.a.length];
        if (p.o == null && q.i == null) {
          b.write('L ${pt(q.p)} ');
        } else {
          b.write('C ${pt(p.o ?? p.p)} ${pt(q.i ?? q.p)} ${pt(q.p)} ');
        }
      }
      if (s.closed) b.write('Z ');
    }
    return b.toString().trim();
  }

  Path toPath(Offset Function(Offset) t) {
    final path = Path();
    for (final s in subs) {
      if (s.a.isEmpty) continue;
      final m = t(s.a[0].p);
      path.moveTo(m.dx, m.dy);
      for (var k = 0; k < s.segCount; k++) {
        final p = s.a[k], q = s.a[(k + 1) % s.a.length];
        final e = t(q.p);
        if (p.o == null && q.i == null) {
          path.lineTo(e.dx, e.dy);
        } else {
          final c1 = t(p.o ?? p.p), c2 = t(q.i ?? q.p);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        }
      }
      if (s.closed) path.close();
    }
    return path;
  }

  /// Nearest segment within [r]: returns [subpathIndex, segmentIndex, t].
  List<double>? hitSeg(Offset pos, double r) {
    var best = r;
    List<double>? res;
    for (var si = 0; si < subs.length; si++) {
      final s = subs[si];
      for (var k = 0; k < s.segCount; k++) {
        final p = s.a[k], q = s.a[(k + 1) % s.a.length];
        for (var j = 0; j <= 24; j++) {
          final t = j / 24;
          final d = (_bez(p, q, t) - pos).distance;
          if (d < best) {
            best = d;
            res = [si.toDouble(), k.toDouble(), t];
          }
        }
      }
    }
    return res;
  }

  /// Insert a node on segment [k] at parameter [t] (de Casteljau split).
  void splitSeg(int si, int k, double t) {
    final s = subs[si];
    final p = s.a[k], q = s.a[(k + 1) % s.a.length];
    Offset l(Offset a, Offset b) => Offset.lerp(a, b, t)!;
    Anchor na;
    if (p.o == null && q.i == null) {
      na = Anchor(l(p.p, q.p));
    } else {
      final c1 = p.o ?? p.p, c2 = q.i ?? q.p;
      final a = l(p.p, c1), b = l(c1, c2), c = l(c2, q.p);
      final d = l(a, b), e = l(b, c);
      na = Anchor(l(d, e), i: d, o: e, smooth: true);
      p.o = a;
      q.i = c;
    }
    s.a.insert(k + 1, na);
  }
}

Matrix4 parseTransform(String? s) {
  final m = Matrix4.identity();
  if (s == null) return m;
  for (final x in RegExp(r'(\w+)\s*\(([^)]*)\)').allMatches(s)) {
    final v = x.group(2)!.split(RegExp(r'[\s,]+')).where((e) => e.isNotEmpty).map((e) => double.tryParse(e) ?? 0).toList();
    double g(int i, [double d = 0]) => i < v.length ? v[i] : d;
    switch (x.group(1)) {
      case 'translate':
        m.translateByVector3(Vector3(g(0), g(1), 0.0));
        break;
      case 'scale':
        m.scaleByVector3(Vector3(g(0), g(1, g(0)), 1.0));
        break;
      case 'rotate':
        m
          ..translateByVector3(Vector3(g(1), g(2), 0.0))
          ..rotateZ(g(0) * math.pi / 180)
          ..translateByVector3(Vector3(-g(1), -g(2), 0.0));
        break;
      case 'matrix':
        m.multiply(Matrix4(g(0), g(1), 0, 0, g(2), g(3), 0, 0, 0, 0, 1, 0, g(4), g(5), 0, 1));
        break;
    }
  }
  return m;
}

List<Offset> _parsePoints(String s) {
  final v = s.split(RegExp(r'[\s,]+')).where((e) => e.isNotEmpty).map(double.tryParse).whereType<double>().toList();
  return [for (var i = 0; i + 1 < v.length; i += 2) Offset(v[i], v[i + 1])];
}

extension SvgNodePath on SvgNode {
  /// The matrix the editor applies around the shape (move / rotate / scale).
  Matrix4 get gMatrix {
    final c = box?.center ?? Offset.zero;
    return Matrix4.translationValues(dx, dy, 0)
      ..translateByVector3(Vector3(c.dx, c.dy, 0.0))
      ..rotateZ(rot * math.pi / 180)
      ..scaleByVector3(Vector3(scale, scale, 1.0))
      ..translateByVector3(Vector3(-c.dx, -c.dy, 0.0));
  }

  bool get hasEditTransform => dx != 0 || dy != 0 || rot != 0 || scale != 1 || attrs.containsKey('transform');

  PathModel _localModel() {
    switch (tag) {
      case 'rect':
        final x = _n('x'), y = _n('y'), w = _n('width'), h = _n('height');
        return PathModel([
          SubPath([Anchor(Offset(x, y)), Anchor(Offset(x + w, y)), Anchor(Offset(x + w, y + h)), Anchor(Offset(x, y + h))], true)
        ]);
      case 'circle':
      case 'ellipse':
        final cx = _n('cx'), cy = _n('cy');
        final rx = tag == 'circle' ? _n('r') : _n('rx');
        final ry = tag == 'circle' ? _n('r') : _n('ry');
        const k = 0.5523;
        return PathModel([
          SubPath([
            Anchor(Offset(cx + rx, cy), i: Offset(cx + rx, cy - ry * k), o: Offset(cx + rx, cy + ry * k), smooth: true),
            Anchor(Offset(cx, cy + ry), i: Offset(cx + rx * k, cy + ry), o: Offset(cx - rx * k, cy + ry), smooth: true),
            Anchor(Offset(cx - rx, cy), i: Offset(cx - rx, cy + ry * k), o: Offset(cx - rx, cy - ry * k), smooth: true),
            Anchor(Offset(cx, cy - ry), i: Offset(cx - rx * k, cy - ry), o: Offset(cx + rx * k, cy - ry), smooth: true),
          ], true)
        ]);
      case 'line':
        return PathModel([SubPath([Anchor(Offset(_n('x1'), _n('y1'))), Anchor(Offset(_n('x2'), _n('y2')))])]);
      case 'polygon':
      case 'polyline':
        return PathModel([SubPath(_parsePoints(attrs['points'] ?? '').map((p) => Anchor(p)).toList(), tag == 'polygon')]);
      default:
        return PathModel.fromD(attrs['d'] ?? '');
    }
  }

  /// Converts any shape to a plain `<path>` with all transforms baked in,
  /// so its nodes can be edited directly in document coordinates.
  void bakeToPath() {
    final model = _localModel();
    final m = gMatrix..multiply(parseTransform(attrs['transform']));
    model.transform(m);
    for (final k in ['x', 'y', 'width', 'height', 'cx', 'cy', 'r', 'rx', 'ry', 'x1', 'y1', 'x2', 'y2', 'points', 'transform']) {
      attrs.remove(k);
    }
    tag = 'path';
    attrs['d'] = model.toD();
    dx = dy = rot = 0;
    scale = 1;
  }
}