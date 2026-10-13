// ============================================================================
// KEYFRAMES: dark monochrome, CapCut style
// ============================================================================
const double _kfFps = 30;

const Color _kfBg = Color(0xFF0D0D0D);
const Color _kfCard = Color(0xFF171717);
const Color _kfLine = Color(0xFF2A2A2A);
const Color _kfLineHi = Color(0xFF3A3A3A);
const Color _kfText = Color(0xFFF2F2F2);
const Color _kfMuted = Color(0xFF8A8A8A);
const Color _kfDim = Color(0xFF555555);

String _kfTimecode(double s) {
  final int fps = _kfFps.toInt();
  final int total = ((s < 0 ? 0.0 : s) * _kfFps).round();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(total ~/ (fps * 60))}:${two((total ~/ fps) % 60)}:${two(total % fps)}';
}

T? _kfFind<T>(Iterable<T> items, bool Function(T) test) {
  for (final T i in items) {
    if (test(i)) return i;
  }
  return null;
}

class _CurveOption {
  const _CurveOption(this.label, this.curve);
  final String label;
  final KeyframeCurve curve;
}

const List<_CurveOption> _kfOptions = <_CurveOption>[
  _CurveOption('Linear', KeyframeCurve.linear),
  _CurveOption('Ease in', KeyframeCurve.easeIn),
  _CurveOption('Ease out', KeyframeCurve.easeOut),
  _CurveOption('In-out', KeyframeCurve.easeInOut),
  _CurveOption('Bounce', KeyframeCurve.bounce),
  _CurveOption('Elastic', KeyframeCurve.elastic),
  _CurveOption('Steps', KeyframeCurve.steps),
  _CurveOption('Random', KeyframeCurve.random),
];

// ----------------------------------------------------------------------------
// Sheet
// ----------------------------------------------------------------------------
class KeyframeSheet extends StatefulWidget {
  const KeyframeSheet({super.key});

  @override
  State<KeyframeSheet> createState() => _KeyframeSheetState();
}

class _KeyframeSheetState extends State<KeyframeSheet> {
  Object? _selId;
  bool _lockScroll = false; // গ্রাফের হ্যান্ডেল টানার সময় লিস্ট স্ক্রল বন্ধ

  void _toast(String msg) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final playhead = context.select<EditorController, Duration>((e) => e.playhead);

    final List<Keyframe> all = <Keyframe>[...?clip?.keyframes]
      ..sort((a, b) => a.time.compareTo(b.time));

    final double total = clip == null ? 1.0 : math.max(secondsOf(clip.duration), 0.1);
    final double rel = clip == null ? 0.0 : secondsOf(playhead - clip.start);
    final bool inClip = clip != null && rel >= 0 && rel <= total;
    final double tol = 0.5 / _kfFps;

    final Keyframe? atHead = _kfFind(all, (k) => (secondsOf(k.time) - rel).abs() < tol);
    final Keyframe? selected = _selId == null ? null : _kfFind(all, (k) => k.id == _selId);

    void seekTo(double s) {
      if (clip == null) return;
      seekPlayhead(editor, secondsOf(clip.start) + s.clamp(0.0, total).toDouble());
    }

    void prev() {
      final List<Keyframe> c = all.where((k) => secondsOf(k.time) < rel - tol).toList();
      if (c.isEmpty) return;
      seekTo(secondsOf(c.last.time));
      setState(() => _selId = c.last.id);
    }

    void next() {
      final List<Keyframe> c = all.where((k) => secondsOf(k.time) > rel + tol).toList();
      if (c.isEmpty) return;
      seekTo(secondsOf(c.first.time));
      setState(() => _selId = c.first.id);
    }

    void toggle() {
      if (atHead != null) {
        editor.removeKeyframe(atHead.id);
        setState(() => _selId = null);
      } else if (!inClip) {
        _toast('Move the playhead inside the clip first.');
      } else {
        editor.addKeyframeAtPlayhead();
      }
    }

    void pick(Keyframe kf, _CurveOption o) {
      tapFeedback();
      final KeyframeCurve cur = kf.curve;
      final bool reroll = o.curve.kind == CurveKind.random && cur.kind == CurveKind.random;
      editor.addKeyframe(kf.copyWith(curve: reroll ? cur.copyWith(seed: cur.seed + 1) : o.curve));
    }

    return ColoredBox(
      color: _kfBg,
      child: ListView(
        physics: (_lockScroll && selected != null) ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(12, 12, 12, 16 + MediaQuery.paddingOf(context).bottom),
        children: <Widget>[
          // ---- prev / diamond / next / timecode / delete --------------------
          _KfCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: <Widget>[
                _KfAction(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Previous keyframe',
                  onTap: clip == null ? null : prev,
                ),
                _KfAction(
                  icon: atHead != null ? Icons.diamond_rounded : Icons.diamond_outlined,
                  tooltip: atHead != null ? 'Remove keyframe' : 'Add keyframe',
                  active: atHead != null,
                  onTap: clip == null ? null : toggle,
                ),
                _KfAction(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Next keyframe',
                  onTap: clip == null ? null : next,
                ),
                Expanded(
                  child: Text(
                    _kfTimecode(rel),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _kfText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                _KfAction(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete selected keyframe',
                  onTap: selected == null
                      ? null
                      : () {
                          editor.removeKeyframe(selected.id);
                          setState(() => _selId = null);
                        },
                ),
              ],
            ),
          ),

          // ---- Track ---------------------------------------------------------
          const SizedBox(height: 10),
          if (clip == null)
            const _KfHint('Select a clip to animate it.')
          else if (all.isEmpty)
            const _KfHint('No keyframes yet. Move the playhead and tap the diamond.')
          else
            _KfCard(
              child: _KfTrack(
                keys: all,
                selectedId: selected?.id,
                total: total,
                playhead: rel,
                onSeek: seekTo,
                onSelect: (k) {
                  if (k == null) {
                    setState(() => _selId = null);
                  } else {
                    seekTo(secondsOf(k.time));
                    setState(() => _selId = k.id);
                  }
                },
              ),
            ),

          // ---- Curve graph + type tiles (শুধু সিলেক্ট করলে) -----------------
          if (selected != null) ...<Widget>[
            const SizedBox(height: 10),
            _KfCard(
              padding: EdgeInsets.zero,
              child: _CurveEditor(
                key: ValueKey<Object?>(selected.id),
                curve: selected.curve,
                onDragState: (b) {
                  if (_lockScroll != b) setState(() => _lockScroll = b);
                },
                onChanged: (c) => editor.addKeyframe(selected.copyWith(curve: c)),
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.1,
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (final _CurveOption o in _kfOptions)
                  _CurveTile(
                    option: o,
                    on: o.curve.sameShape(selected.curve),
                    onTap: () => pick(selected, o),
                  ),
              ],
            ),
          ] else if (all.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: _KfHint('Tap a diamond to edit its curve.'),
            ),

          const SizedBox(height: 16),
          _kfOutlineButton(
            'Clear all keyframes',
            all.isEmpty
                ? null
                : () {
                    for (final Keyframe k in all) {
                      editor.removeKeyframe(k.id);
                    }
                    setState(() {
                      _selId = null;
                      _lockScroll = false;
                    });
                  },
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Small widgets
// ----------------------------------------------------------------------------
class _KfCard extends StatelessWidget {
  const _KfCard({required this.child, this.padding = const EdgeInsets.all(6)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _kfCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kfLine),
        ),
        child: child,
      );
}

class _KfHint extends StatelessWidget {
  const _KfHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kfMuted, fontSize: 13),
        ),
      );
}

Widget _kfOutlineButton(String label, VoidCallback? onTap) => SizedBox(
      height: 44,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kfText,
          disabledForegroundColor: _kfDim,
          side: BorderSide(color: onTap == null ? _kfLine : _kfLineHi),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap == null
            ? null
            : () {
                tapFeedback();
                onTap();
              },
        child: Text(label),
      ),
    );

class _KfAction extends StatelessWidget {
  const _KfAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color fg = onTap == null ? _kfDim : (active ? _kfBg : _kfText);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                tapFeedback();
                onTap!();
              },
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _kfText : Colors.transparent,
          ),
          child: Icon(icon, size: 22, color: fg),
        ),
      ),
    );
  }
}

class _CurveTile extends StatelessWidget {
  const _CurveTile({required this.option, required this.on, required this.onTap});
  final _CurveOption option;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius r = BorderRadius.circular(10);
    return Material(
      color: on ? _kfText : _kfCard,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: on ? _kfText : _kfLine),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CustomPaint(
                size: const Size(28, 28),
                painter: _CurveIconPainter(option.curve, on ? _kfBg : _kfMuted),
              ),
              const SizedBox(height: 6),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: on ? _kfBg : _kfMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Track (single lane)
// ----------------------------------------------------------------------------
class _KfTrack extends StatelessWidget {
  const _KfTrack({
    required this.keys,
    required this.selectedId,
    required this.total,
    required this.playhead,
    required this.onSeek,
    required this.onSelect,
  });

  final List<Keyframe> keys; // time অনুযায়ী সাজানো
  final Object? selectedId;
  final double total;
  final double playhead;
  final ValueChanged<double> onSeek;
  final ValueChanged<Keyframe?> onSelect;

  static const double _pad = 16;
  static const double _h = 56;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final double w = c.maxWidth;
      final double usable = math.max(w - _pad * 2, 1);
      double xOf(double sec) => _pad + sec / total * usable;
      double secOf(double dx) => ((dx - _pad) / usable * total).clamp(0.0, total).toDouble();

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          Keyframe? hit;
          double best = 22; // সবচেয়ে কাছের ডায়মন্ড, ২২px-এর মধ্যে
          for (final Keyframe k in keys) {
            final double dist = (xOf(secondsOf(k.time)) - d.localPosition.dx).abs();
            if (dist < best) {
              best = dist;
              hit = k;
            }
          }
          tapFeedback();
          if (hit != null) {
            onSelect(hit);
          } else {
            onSeek(secOf(d.localPosition.dx));
            onSelect(null);
          }
        },
        onHorizontalDragUpdate: (d) => onSeek(secOf(d.localPosition.dx)),
        child: CustomPaint(
          size: Size(w, _h),
          painter: _TrackPainter(
            keys: keys,
            selectedId: selectedId,
            xOf: xOf,
            playheadX: xOf(playhead.clamp(0.0, total).toDouble()),
          ),
        ),
      );
    });
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.keys,
    required this.selectedId,
    required this.xOf,
    required this.playheadX,
  });

  final List<Keyframe> keys;
  final Object? selectedId;
  final double Function(double) xOf;
  final double playheadX;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;

    canvas.drawLine(
      Offset(16, cy),
      Offset(size.width - 16, cy),
      Paint()
        ..color = _kfLineHi
        ..strokeWidth = 2,
    );

    final Paint seg = Paint()
      ..color = _kfDim
      ..strokeWidth = 2;
    for (int i = 0; i + 1 < keys.length; i++) {
      canvas.drawLine(
        Offset(xOf(secondsOf(keys[i].time)), cy),
        Offset(xOf(secondsOf(keys[i + 1].time)), cy),
        seg,
      );
    }

    for (final Keyframe k in keys) {
      final double x = xOf(secondsOf(k.time));
      final bool on = k.id == selectedId;
      final Path p = Path()
        ..moveTo(x, cy - 8)
        ..lineTo(x + 8, cy)
        ..lineTo(x, cy + 8)
        ..lineTo(x - 8, cy)
        ..close();
      canvas.drawPath(p, Paint()..color = on ? _kfText : _kfBg);
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = on ? _kfBg : _kfMuted,
      );
    }

    final Paint ph = Paint()
      ..color = _kfText
      ..strokeWidth = 2;
    canvas.drawLine(Offset(playheadX, 6), Offset(playheadX, size.height - 4), ph);
    canvas.drawCircle(Offset(playheadX, 6), 3.5, ph);
  }

  @override
  bool shouldRepaint(covariant _TrackPainter o) => true;
}

// ----------------------------------------------------------------------------
// Curve editor (bezier-এ হ্যান্ডেল টানা যায়, বাকিগুলোয় শুধু প্রিভিউ)
// ----------------------------------------------------------------------------
class _GraphMap {
  const _GraphMap(this.size);
  final Size size;

  static const double pad = 16;
  static const double yMin = -0.4;
  static const double yMax = 1.4;

  Rect get r => Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);

  Offset toPx(double x, double y) => Offset(
        r.left + x * r.width,
        r.bottom - (y - yMin) / (yMax - yMin) * r.height,
      );

  double xOf(double px) => ((px - r.left) / r.width).clamp(0.0, 1.0).toDouble();

  double yOf(double py) =>
      (yMin + (r.bottom - py) / r.height * (yMax - yMin)).clamp(yMin, yMax).toDouble();
}

class _CurveEditor extends StatefulWidget {
  const _CurveEditor({
    super.key,
    required this.curve,
    required this.onChanged,
    required this.onDragState,
  });

  final KeyframeCurve curve;
  final ValueChanged<KeyframeCurve> onChanged;
  final ValueChanged<bool> onDragState;

  @override
  State<_CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<_CurveEditor> {
  static const double _height = 200;

  late KeyframeCurve _curve = widget.curve;
  int _active = -1; // -1 = কিছু ধরা নেই, 0 = প্রথম হ্যান্ডেল, 1 = দ্বিতীয়

  @override
  void didUpdateWidget(covariant _CurveEditor old) {
    super.didUpdateWidget(old);
    if (_active == -1) _curve = widget.curve; // টাইল চাপলে বা বাইরে বদলালে সিঙ্ক
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final _GraphMap map = _GraphMap(Size(c.maxWidth, _height));

      void move(Offset p) {
        final double x = map.xOf(p.dx);
        final double y = map.yOf(p.dy);
        setState(() {
          _curve = _active == 0 ? _curve.copyWith(x1: x, y1: y) : _curve.copyWith(x2: x, y2: y);
        });
      }

      void finish() {
        if (_active == -1) return;
        _active = -1;
        widget.onDragState(false);
        widget.onChanged(_curve); // আঙুল তুললে বা cancel হলেও সেভ হবে
      }

      // Listener ব্যবহার করেছি যাতে ListView-এর স্ক্রলের সাথে gesture লড়াই না হয়।
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (!_curve.isBezier || _active != -1) return;
          final double d0 = (map.toPx(_curve.x1, _curve.y1) - e.localPosition).distance;
          final double d1 = (map.toPx(_curve.x2, _curve.y2) - e.localPosition).distance;
          if (math.min(d0, d1) > 36) return;
          _active = d0 <= d1 ? 0 : 1;
          widget.onDragState(true);
          move(e.localPosition);
        },
        onPointerMove: (e) {
          if (_active != -1) move(e.localPosition);
        },
        onPointerUp: (_) => finish(),
        onPointerCancel: (_) => finish(),
        child: CustomPaint(
          size: map.size,
          painter: _CurveGraphPainter(_curve, map),
        ),
      );
    });
  }
}

class _CurveGraphPainter extends CustomPainter {
  _CurveGraphPainter(this.curve, this.map);
  final KeyframeCurve curve;
  final _GraphMap map;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    // গ্রিড
    final Paint grid = Paint()
      ..color = _kfLine
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final double f = i / 4;
      canvas.drawLine(map.toPx(f, 0), map.toPx(f, 1), grid);
      canvas.drawLine(map.toPx(0, f), map.toPx(1, f), grid);
    }
    canvas.drawRect(
      Rect.fromPoints(map.toPx(0, 1), map.toPx(1, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _kfLineHi
        ..strokeWidth = 1,
    );

    final Offset start = map.toPx(0, 0);
    final Offset end = map.toPx(1, 1);
    final Offset h1 = map.toPx(curve.x1, curve.y1);
    final Offset h2 = map.toPx(curve.x2, curve.y2);

    // হ্যান্ডেলের লাইন (শুধু bezier)
    if (curve.isBezier) {
      final Paint guide = Paint()
        ..color = _kfDim
        ..strokeWidth = 1.2;
      canvas.drawLine(start, h1, guide);
      canvas.drawLine(end, h2, guide);
    }

    // কার্ভ
    const int n = 120;
    final Path path = Path();
    for (int i = 0; i <= n; i++) {
      final double t = i / n;
      final Offset o = map.toPx(t, curve.transform(t));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _kfText,
    );

    // দুই প্রান্ত
    final Paint dot = Paint()..color = _kfText;
    canvas.drawCircle(start, 4, dot);
    canvas.drawCircle(end, 4, dot);

    // টানার হ্যান্ডেল (শুধু bezier)
    if (curve.isBezier) {
      for (final Offset o in <Offset>[h1, h2]) {
        canvas.drawCircle(o, 10, Paint()..color = _kfText);
        canvas.drawCircle(
          o,
          10,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = _kfBg,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CurveGraphPainter o) => o.curve != curve || o.map.size != map.size;
}

// ----------------------------------------------------------------------------
// টাইলের ছোট আইকন (কার্ভের নিজের আকার)
// ----------------------------------------------------------------------------
class _CurveIconPainter extends CustomPainter {
  _CurveIconPainter(this.curve, this.color);
  final KeyframeCurve curve;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const double pad = 4;
    final double w = size.width - pad * 2;
    final double h = size.height - pad * 2;
    final Path path = Path();
    for (int i = 0; i <= 48; i++) {
      final double t = i / 48;
      final double y = curve.transform(t).clamp(-0.25, 1.25).toDouble();
      final double px = pad + t * w;
      final double py = size.height - pad - y * h;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CurveIconPainter o) => o.curve != curve || o.color != color;
}