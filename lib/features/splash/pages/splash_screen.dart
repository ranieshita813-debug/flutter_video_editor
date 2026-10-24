// lib/features/splash/splash_screen.dart
//
// Splash redesign (CapCut-style): dark canvas, bold wordmark, one short
// signature animation, then straight into the app.
//
//  1. Soft accent glow fades in behind the wordmark.
//  2. "motionGr" rises letter by letter out of a mask ("motion" white, "Gr" accent).
//  3. Short hold, then navigate to '/home'.
//
// Font: Unbounded (SIL OFL). Bundle it so there is no fallback flash:
//
//   # pubspec.yaml
//   flutter:
//     fonts:
//       - family: Unbounded
//         fonts:
//           - asset: assets/fonts/Unbounded-Bold.ttf
//             weight: 700
//
// No flutter_svg / image asset is needed any more.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _bg = Color(0xFF0B0B0D);
const Color _accent = Color(0xFF2DE2E6);
const Color _text = Color(0xFFFFFFFF);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const String _word = 'motionGr';
  static const int _accentFrom = 6; // "Gr" starts here
  static const double _fontSize = 40;

  late final AnimationController _c;
  bool _started = false;

  // Glow fades in over the first 40% of the timeline.
  static const Interval _glowT = Interval(0.0, 0.40, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run(reduceMotion: MediaQuery.of(context).disableAnimations);
  }

  Future<void> _run({required bool reduceMotion}) async {
    if (reduceMotion) {
      _c.value = 1;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } else {
      await _c.forward();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (mounted) Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Letter i rises between ~5% and ~63% of the timeline, staggered.
  double _letterT(int i) {
    final double start = 0.05 + i * 0.045;
    return Interval(start, start + 0.26, curve: Curves.easeOutCubic)
        .transform(_c.value);
  }

  Widget _wordmark() {
    final List<Widget> letters = <Widget>[];
    for (int i = 0; i < _word.length; i++) {
      final double t = _letterT(i);
      letters.add(
        Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            // Slides up from below; the ClipRect below acts as the mask.
            offset: Offset(0, (1 - t) * _fontSize * 1.2),
            child: Text(
              _word[i],
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: _fontSize,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -1,
                color: i >= _accentFrom ? _accent : _text,
              ),
            ),
          ),
        ),
      );
    }
    return ClipRect(
      child: Row(mainAxisSize: MainAxisSize.min, children: letters),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _bg,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: _bg,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (BuildContext context, Widget? _) {
              final double glow = _glowT.transform(_c.value);

              return Semantics(
                label: 'motionGr',
                child: ExcludeSemantics(
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      // Soft accent glow behind the wordmark.
                      Opacity(
                        opacity: glow,
                        child: Transform.scale(
                          scale: 0.85 + 0.15 * glow,
                          child: Container(
                            width: 380,
                            height: 380,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: <Color>[
                                  _accent.withAlpha(46),
                                  _accent.withAlpha(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _wordmark(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}