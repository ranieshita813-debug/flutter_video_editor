// core/models/chroma_key.dart
//
// Chroma key (Ultra-Key style) model.
//  - Preview : see chroma_key_preview.dart  (fragment shader)
//  - Export  : toFfmpegFilter()             (FFmpeg filter graph)

import 'dart:ui';

enum ChromaOutput { composite, matte, source }

enum ChromaPreset { defaultKey, greenScreen, blueScreen, aggressive, softEdges, relaxed }

class ChromaKey {
  // ---- defaults (used for double-tap-to-reset in the sheet) ----
  static const double dSimilarity = 40, dSmoothness = 20, dMidPoint = 50;
  static const double dSpill = 50, dSpillRange = 50, dSaturation = 100;

  final bool enabled;
  final Color keyColor;
  final ChromaOutput output;

  // Key / Matte generation (0..100)
  final double similarity; // Tolerance
  final double smoothness; // Transparency / edge blend
  final double highlight;
  final double shadow;
  final double pedestal;

  // Matte cleanup
  final double choke; // -100..100 (negative = grow, positive = shrink)
  final double soften; // 0..100
  final double contrast; // 0..100
  final double midPoint; // 0..100

  // Spill suppression (0..100)
  final double spill;
  final double spillRange;
  final double desaturate;
  final double spillLuma;

  // Colour correction
  final double saturation; // 0..200 (100 = unchanged)
  final double hue; // -180..180
  final double luminance; // -100..100

  const ChromaKey({
    this.enabled = false,
    this.keyColor = const Color(0xFF00B140),
    this.output = ChromaOutput.composite,
    this.similarity = dSimilarity,
    this.smoothness = dSmoothness,
    this.highlight = 0,
    this.shadow = 0,
    this.pedestal = 0,
    this.choke = 0,
    this.soften = 0,
    this.contrast = 0,
    this.midPoint = dMidPoint,
    this.spill = dSpill,
    this.spillRange = dSpillRange,
    this.desaturate = 0,
    this.spillLuma = 0,
    this.saturation = dSaturation,
    this.hue = 0,
    this.luminance = 0,
  });

  ChromaKey copyWith({
    bool? enabled,
    Color? keyColor,
    ChromaOutput? output,
    double? similarity,
    double? smoothness,
    double? highlight,
    double? shadow,
    double? pedestal,
    double? choke,
    double? soften,
    double? contrast,
    double? midPoint,
    double? spill,
    double? spillRange,
    double? desaturate,
    double? spillLuma,
    double? saturation,
    double? hue,
    double? luminance,
  }) =>
      ChromaKey(
        enabled: enabled ?? this.enabled,
        keyColor: keyColor ?? this.keyColor,
        output: output ?? this.output,
        similarity: similarity ?? this.similarity,
        smoothness: smoothness ?? this.smoothness,
        highlight: highlight ?? this.highlight,
        shadow: shadow ?? this.shadow,
        pedestal: pedestal ?? this.pedestal,
        choke: choke ?? this.choke,
        soften: soften ?? this.soften,
        contrast: contrast ?? this.contrast,
        midPoint: midPoint ?? this.midPoint,
        spill: spill ?? this.spill,
        spillRange: spillRange ?? this.spillRange,
        desaturate: desaturate ?? this.desaturate,
        spillLuma: spillLuma ?? this.spillLuma,
        saturation: saturation ?? this.saturation,
        hue: hue ?? this.hue,
        luminance: luminance ?? this.luminance,
      );

  /// Reset every parameter, keep the key colour and enabled state.
  ChromaKey reset() => ChromaKey(enabled: enabled, keyColor: keyColor);

  /// Presets keep the picked key colour.
  ChromaKey applyPreset(ChromaPreset p) {
    final base = reset();
    switch (p) {
      case ChromaPreset.defaultKey:
        return base;
      case ChromaPreset.greenScreen:
        return base.copyWith(keyColor: const Color(0xFF00B140), similarity: 42, smoothness: 18, spill: 60);
      case ChromaPreset.blueScreen:
        return base.copyWith(keyColor: const Color(0xFF0047BB), similarity: 42, smoothness: 18, spill: 60);
      case ChromaPreset.aggressive:
        return base.copyWith(similarity: 65, smoothness: 12, choke: 15, spill: 80, spillRange: 65, pedestal: 6);
      case ChromaPreset.softEdges:
        return base.copyWith(similarity: 38, smoothness: 40, soften: 25, contrast: 20, spill: 55);
      case ChromaPreset.relaxed:
        return base.copyWith(similarity: 25, smoothness: 25, spill: 35, spillRange: 40);
    }
  }

  // ---------------------------------------------------------------- JSON
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'keyColor': keyColor.value,
        'output': output.index,
        'similarity': similarity,
        'smoothness': smoothness,
        'highlight': highlight,
        'shadow': shadow,
        'pedestal': pedestal,
        'choke': choke,
        'soften': soften,
        'contrast': contrast,
        'midPoint': midPoint,
        'spill': spill,
        'spillRange': spillRange,
        'desaturate': desaturate,
        'spillLuma': spillLuma,
        'saturation': saturation,
        'hue': hue,
        'luminance': luminance,
      };

  factory ChromaKey.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return ChromaKey(
      enabled: j['enabled'] as bool? ?? false,
      keyColor: Color((j['keyColor'] as int?) ?? 0xFF00B140),
      output: ChromaOutput.values[(j['output'] as int?) ?? 0],
      similarity: d('similarity', dSimilarity),
      smoothness: d('smoothness', dSmoothness),
      highlight: d('highlight', 0),
      shadow: d('shadow', 0),
      pedestal: d('pedestal', 0),
      choke: d('choke', 0),
      soften: d('soften', 0),
      contrast: d('contrast', 0),
      midPoint: d('midPoint', dMidPoint),
      spill: d('spill', dSpill),
      spillRange: d('spillRange', dSpillRange),
      desaturate: d('desaturate', 0),
      spillLuma: d('spillLuma', 0),
      saturation: d('saturation', dSaturation),
      hue: d('hue', 0),
      luminance: d('luminance', 0),
    );
  }

  // ------------------------------------------------------------- FFmpeg
  String _hex(Color c) => (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  /// Returns a filter-graph fragment: `[input] ... [output]`.
  /// Use inside -filter_complex, then overlay `[output]` on the background.
  ///
  /// Not mapped in FFmpeg (preview only): highlight, shadow, desaturate.
  String toFfmpegFilter({String input = '0:v', String output = 'keyed'}) {
    final sim = (0.005 + similarity / 100 * 0.495).toStringAsFixed(3);
    final blend = (smoothness / 100 * 0.5).toStringAsFixed(3);

    final color = <String>[
      'format=yuva444p',
      'chromakey=color=0x${_hex(keyColor)}:similarity=$sim:blend=$blend',
    ];

    // Spill suppression (FFmpeg's despill supports green / blue only)
    if (spill > 0) {
      final r = keyColor.red, g = keyColor.green, b = keyColor.blue;
      final isGreen = g >= b && g > r;
      final isBlue = b > g && b > r;
      if (isGreen || isBlue) {
        final mix = (spill / 100).toStringAsFixed(2);
        final expand = (spillRange / 100).toStringAsFixed(2);
        final bright = (spillLuma / 100).toStringAsFixed(2);
        color.add('despill=type=${isGreen ? 'green' : 'blue'}:mix=$mix:expand=$expand:brightness=$bright');
      }
    }

    // Colour correction
    if (saturation != dSaturation || hue != 0) {
      color.add('hue=h=${hue.toStringAsFixed(1)}:s=${(saturation / 100).toStringAsFixed(2)}');
    }
    if (luminance != 0) {
      color.add('eq=brightness=${(luminance / 200).toStringAsFixed(3)}');
    }

    // Matte cleanup (operates on the alpha plane)
    final matte = <String>[];
    if (pedestal > 0) {
      final p = (pedestal / 100 * 128);
      final s = 255 / (255 - p);
      matte.add("lut=y='clip((val-${p.toStringAsFixed(1)})*${s.toStringAsFixed(3)}\\,0\\,maxval)'");
    }
    if (choke != 0) {
      final n = (choke.abs() / 25).ceil().clamp(1, 4);
      matte.addAll(List.filled(n, choke > 0 ? 'erosion' : 'dilation'));
    }
    if (contrast > 0) {
      final m = midPoint / 100 * 255;
      final k = 1 + contrast / 25;
      matte.add("lut=y='clip((val-${m.toStringAsFixed(1)})*${k.toStringAsFixed(2)}+${m.toStringAsFixed(1)}\\,0\\,maxval)'");
    }
    if (soften > 0) {
      matte.add('gblur=sigma=${(soften / 100 * 6).toStringAsFixed(2)}');
    }

    final base = '[$input]${color.join(',')}';
    if (matte.isEmpty) return '$base[$output]';

    return '$base[k0];'
        '[k0]split[c][m0];'
        '[m0]alphaextract,${matte.join(',')}[m];'
        '[c][m]alphamerge[$output]';
  }
}