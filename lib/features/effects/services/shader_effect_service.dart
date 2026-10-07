import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/effects/services/shader_database_service.dart';

class ShaderEffectService extends ChangeNotifier {
  ShaderEffectService() {
    _initService();
  }

  bool _isLoading = true;
  String _searchQuery = '';
  ShaderEffectCategory _selectedCategory = ShaderEffectCategory.all;
  bool _showFavoritesOnly = false;
  bool _showDownloadedOnly = false;

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  ShaderEffectCategory get selectedCategory => _selectedCategory;
  bool get showFavoritesOnly => _showFavoritesOnly;
  bool get showDownloadedOnly => _showDownloadedOnly;

  Future<void> _initService() async {
    _isLoading = true;
    notifyListeners();

    try {
      final seeds = _getBuiltInEffectSeeds();
      await ShaderDatabaseService.instance.initialize(seeds: seeds);
      _isLoading = false;
      notifyListeners();
    } catch (e, stack) {
      AppLogger.error('Error initializing ShaderEffectService',
          tag: 'ShaderEffectService', error: e, stackTrace: stack);
      _isLoading = false;
      notifyListeners();
    }
  }

  List<ShaderEffect> get filteredEffects {
    var list = ShaderDatabaseService.instance.fetchAllEffects();

    if (_selectedCategory != ShaderEffectCategory.all) {
      list = list.where((e) => e.category == _selectedCategory).toList();
    }

    if (_showFavoritesOnly) {
      list = list.where((e) => e.isFavorite).toList();
    }

    if (_showDownloadedOnly) {
      list = list.where((e) => e.isDownloaded).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list.where((e) {
        return e.name.toLowerCase().contains(q) ||
            e.description.toLowerCase().contains(q) ||
            e.category.displayName.toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectCategory(ShaderEffectCategory category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void toggleFavoritesFilter() {
    _showFavoritesOnly = !_showFavoritesOnly;
    notifyListeners();
  }

  void toggleDownloadedFilter() {
    _showDownloadedOnly = !_showDownloadedOnly;
    notifyListeners();
  }

  Future<void> toggleFavorite(String effectId) async {
    await ShaderDatabaseService.instance.toggleFavorite(effectId);
    notifyListeners();
  }

  ShaderEffectClip createClipFromEffect(
    ShaderEffect effect, {
    required Duration start,
    required Duration duration,
    int zIndex = 0,
  }) {
    final defaultParams = <String, dynamic>{};
    for (final param in effect.parameters) {
      defaultParams[param.id] = param.value;
    }

    return ShaderEffectClip(
      id: 'shader_${DateTime.now().millisecondsSinceEpoch}',
      effectId: effect.id,
      name: effect.name,
      start: start,
      end: start + duration,
      isEnabled: true,
      zIndex: zIndex,
      parameterValues: defaultParams,
      keyframeAnimations: <KeyframeAnimation>[],
    );
  }

  Map<String, dynamic> evaluateParametersAt(ShaderEffectClip clip, Duration playheadTime) {
    final relativeTime = playheadTime - clip.start;
    return clip.getInterpolatedParameters(relativeTime);
  }

  static List<ShaderEffect> _getBuiltInEffectSeeds() {
    return <ShaderEffect>[
      const ShaderEffect(
        id: 'neon_glow',
        name: 'Neon Glow',
        description: 'Vibrant glowing neon edges with customizable intensity and hue.',
        category: ShaderEffectCategory.glow,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/neon_glow.png',
        isFavorite: true,
        isDownloaded: true,
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'intensity',
            name: 'intensity',
            label: 'Intensity',
            type: ParameterType.float,
            value: 0.8,
            defaultValue: 0.8,
            min: 0.0,
            max: 2.0,
          ),
          ShaderParameter(
            id: 'glowStrength',
            name: 'glowStrength',
            label: 'Glow Strength',
            type: ParameterType.float,
            value: 1.2,
            defaultValue: 1.0,
            min: 0.0,
            max: 3.0,
          ),
          ShaderParameter(
            id: 'tintColor',
            name: 'tintColor',
            label: 'Glow Color',
            type: ParameterType.color,
            value: Color(0xFF00E5FF),
            defaultValue: Color(0xFF00E5FF),
          ),
        ],
        shaderSource: '''
#version 300 es
precision mediump float;
in vec2 v_texCoord;
out vec4 fragColor;
uniform sampler2D u_texture;
uniform float u_intensity;
uniform float u_glowStrength;

void main() {
    vec4 col = texture(u_texture, v_texCoord);
    vec3 glow = col.rgb * u_glowStrength;
    fragColor = vec4(mix(col.rgb, glow, u_intensity), col.a);
}
''',
      ),
      const ShaderEffect(
        id: 'soft_blur',
        name: 'Soft Blur',
        description: 'Smooth atmospheric Gaussian blur for subtle background depth.',
        category: ShaderEffectCategory.blur,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/soft_blur.png',
        isFavorite: false,
        isDownloaded: true,
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'blurAmount',
            name: 'blurAmount',
            label: 'Blur Amount',
            type: ParameterType.float,
            value: 0.5,
            defaultValue: 0.5,
            min: 0.0,
            max: 2.0,
          ),
          ShaderParameter(
            id: 'intensity',
            name: 'intensity',
            label: 'Opacity',
            type: ParameterType.float,
            value: 1.0,
            defaultValue: 1.0,
            min: 0.0,
            max: 1.0,
          ),
        ],
        shaderSource: '''
#version 300 es
precision mediump float;
in vec2 v_texCoord;
out vec4 fragColor;
uniform sampler2D u_texture;
uniform float u_blurAmount;

void main() {
    fragColor = texture(u_texture, v_texCoord);
}
''',
      ),
      const ShaderEffect(
        id: 'vignette_bloom',
        name: 'Vignette Bloom',
        description: 'Soft dark edge vignetting paired with high dynamic range bloom.',
        category: ShaderEffectCategory.bloom,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/vignette_bloom.png',
        isFavorite: true,
        isDownloaded: true,
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'vignette',
            name: 'vignette',
            label: 'Vignette Darkening',
            type: ParameterType.float,
            value: 0.6,
            defaultValue: 0.5,
            min: 0.0,
            max: 1.0,
          ),
          ShaderParameter(
            id: 'brightness',
            name: 'brightness',
            label: 'Bloom Brightness',
            type: ParameterType.float,
            value: 0.15,
            defaultValue: 0.1,
            min: -0.5,
            max: 0.5,
          ),
          ShaderParameter(
            id: 'contrast',
            name: 'contrast',
            label: 'Contrast',
            type: ParameterType.float,
            value: 1.2,
            defaultValue: 1.0,
            min: 0.5,
            max: 2.0,
          ),
        ],
      ),
      const ShaderEffect(
        id: 'vintage_film',
        name: 'Vintage Film',
        description: 'Classic 35mm film aesthetic with warm sepia tones and grain.',
        category: ShaderEffectCategory.vintage,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/vintage_film.png',
        isFavorite: false,
        isDownloaded: true,
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'saturation',
            name: 'saturation',
            label: 'Film Saturation',
            type: ParameterType.float,
            value: 0.75,
            defaultValue: 0.8,
            min: 0.0,
            max: 2.0,
          ),
          ShaderParameter(
            id: 'tintColor',
            name: 'tintColor',
            label: 'Film Warmth',
            type: ParameterType.color,
            value: Color(0x33FFB300),
            defaultValue: Color(0x33FFB300),
          ),
          ShaderParameter(
            id: 'contrast',
            name: 'contrast',
            label: 'Contrast',
            type: ParameterType.float,
            value: 1.1,
            defaultValue: 1.0,
            min: 0.5,
            max: 2.0,
          ),
        ],
      ),
      const ShaderEffect(
        id: 'glitch_scanlines',
        name: 'Glitch Scanlines',
        description: 'Retro CRT monitor scanlines with digital signal chromatic distortion.',
        category: ShaderEffectCategory.glitch,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/glitch_scanlines.png',
        isFavorite: true,
        isDownloaded: true,
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'distortionAmount',
            name: 'distortionAmount',
            label: 'Glitch Distortion',
            type: ParameterType.float,
            value: 0.7,
            defaultValue: 0.5,
            min: 0.0,
            max: 2.0,
          ),
          ShaderParameter(
            id: 'speed',
            name: 'speed',
            label: 'Flicker Speed',
            type: ParameterType.float,
            value: 1.5,
            defaultValue: 1.0,
            min: 0.1,
            max: 3.0,
          ),
        ],
      ),
      const ShaderEffect(
        id: 'warm_sunset',
        name: 'Warm Sunset',
        description: 'Golden hour sunset tone map with rich orange hues.',
        category: ShaderEffectCategory.colorStyle,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/warm_sunset.png',
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'brightness',
            name: 'brightness',
            label: 'Brightness',
            type: ParameterType.float,
            value: 0.1,
            defaultValue: 0.1,
            min: -0.5,
            max: 0.5,
          ),
          ShaderParameter(
            id: 'saturation',
            name: 'saturation',
            label: 'Saturation',
            type: ParameterType.float,
            value: 1.3,
            defaultValue: 1.2,
            min: 0.0,
            max: 2.0,
          ),
          ShaderParameter(
            id: 'tintColor',
            name: 'tintColor',
            label: 'Golden Hue',
            type: ParameterType.color,
            value: Color(0x33FF6B00),
            defaultValue: Color(0x33FF6B00),
          ),
        ],
      ),
      const ShaderEffect(
        id: 'cold_night',
        name: 'Cold Night',
        description: 'Deep blue night tone grading with high contrast shadows.',
        category: ShaderEffectCategory.colorStyle,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/cold_night.png',
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'contrast',
            name: 'contrast',
            label: 'Contrast',
            type: ParameterType.float,
            value: 1.3,
            defaultValue: 1.2,
            min: 0.5,
            max: 2.0,
          ),
          ShaderParameter(
            id: 'tintColor',
            name: 'tintColor',
            label: 'Midnight Blue Tint',
            type: ParameterType.color,
            value: Color(0x40003366),
            defaultValue: Color(0x40003366),
          ),
        ],
      ),
      const ShaderEffect(
        id: 'cinematic_contrast',
        name: 'Cinematic Contrast',
        description: 'Hollywood blockbuster blockbuster teal & orange contrast curve.',
        category: ShaderEffectCategory.cinematic,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/cinematic_contrast.png',
        isFavorite: true,
        isDownloaded: true,
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'contrast',
            name: 'contrast',
            label: 'Contrast',
            type: ParameterType.float,
            value: 1.35,
            defaultValue: 1.2,
            min: 0.5,
            max: 2.0,
          ),
          ShaderParameter(
            id: 'vignette',
            name: 'vignette',
            label: 'Vignette',
            type: ParameterType.float,
            value: 0.4,
            defaultValue: 0.3,
            min: 0.0,
            max: 1.0,
          ),
        ],
      ),
      const ShaderEffect(
        id: 'distorted_edge',
        name: 'Distorted Edge',
        description: 'Lens refraction edge warping and subtle radial distortion.',
        category: ShaderEffectCategory.distortion,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/distorted_edge.png',
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'distortionAmount',
            name: 'distortionAmount',
            label: 'Refraction Distortion',
            type: ParameterType.float,
            value: 0.6,
            defaultValue: 0.5,
            min: 0.0,
            max: 2.0,
          ),
        ],
      ),
      const ShaderEffect(
        id: 'dreamy_light_leak',
        name: 'Dreamy Light Leak',
        description: 'Warm organic optical lens light leaks drifting across the frame.',
        category: ShaderEffectCategory.lightLeak,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/dreamy_light_leak.png',
        isFavorite: true,
        isDownloaded: true,
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'intensity',
            name: 'intensity',
            label: 'Leak Intensity',
            type: ParameterType.float,
            value: 0.85,
            defaultValue: 0.8,
            min: 0.0,
            max: 1.5,
          ),
          ShaderParameter(
            id: 'speed',
            name: 'speed',
            label: 'Drift Speed',
            type: ParameterType.float,
            value: 1.0,
            defaultValue: 1.0,
            min: 0.2,
            max: 3.0,
          ),
        ],
      ),
      const ShaderEffect(
        id: 'noir_darkness',
        name: 'Noir Darkness',
        description: 'High contrast black and white film style with deep shadows.',
        category: ShaderEffectCategory.noir,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/noir_darkness.png',
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'saturation',
            name: 'saturation',
            label: 'Saturation',
            type: ParameterType.float,
            value: 0.0,
            defaultValue: 0.0,
            min: 0.0,
            max: 1.0,
          ),
          ShaderParameter(
            id: 'contrast',
            name: 'contrast',
            label: 'Contrast',
            type: ParameterType.float,
            value: 1.6,
            defaultValue: 1.4,
            min: 0.5,
            max: 2.5,
          ),
        ],
      ),
      const ShaderEffect(
        id: 'cyber_matrix',
        name: 'Cyber Matrix',
        description: 'Futuristic matrix digital code rain visual aesthetic.',
        category: ShaderEffectCategory.neon,
        type: EffectType.builtIn,
        thumbnailUrl: 'assets/effects/cyber_matrix.png',
        parameters: <ShaderParameter>[
          ShaderParameter(
            id: 'tintColor',
            name: 'tintColor',
            label: 'Matrix Color',
            type: ParameterType.color,
            value: Color(0xFF00FF66),
            defaultValue: Color(0xFF00FF66),
          ),
          ShaderParameter(
            id: 'intensity',
            name: 'intensity',
            label: 'Intensity',
            type: ParameterType.float,
            value: 1.0,
            defaultValue: 1.0,
            min: 0.0,
            max: 2.0,
          ),
        ],
      ),
    ];
  }
}
