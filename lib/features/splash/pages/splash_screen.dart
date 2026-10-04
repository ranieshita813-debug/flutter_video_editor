import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const String _title = 'motionGr';
  static const double _waveAmplitude = 14.0;
  static const double _waveCycles = 2.0;
  static const double _letterPhaseShift = 0.55;

  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
    );

    _controller.forward().then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = GoogleFonts.unbounded(
      fontSize: 44,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 1.0,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double t = _controller.value;
            // The wave settles to zero as the animation ends.
            final double damping = 1.0 - Curves.easeInOut.transform(t);

            return Opacity(
              opacity: _fade.value,
              child: Semantics(
                label: _title,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(_title.length, (int i) {
                      final double offsetY = math.sin(
                            t * 2 * math.pi * _waveCycles -
                                i * _letterPhaseShift,
                          ) *
                          _waveAmplitude *
                          damping;

                      return Transform.translate(
                        offset: Offset(0, offsetY),
                        child: Text(_title[i], style: style),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
