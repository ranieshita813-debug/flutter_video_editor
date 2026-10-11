import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/core/services/firebase_service.dart';
import 'package:flutter_video_editor/features/effects/services/shader_database_service.dart';

class RemoteFontItem {
  const RemoteFontItem({
    required this.id,
    required this.name,
    required this.family,
    required this.downloadUrl,
    this.isDownloaded = false,
  });

  final String id;
  final String name;
  final String family;
  final String downloadUrl;
  final bool isDownloaded;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'family': family,
        'downloadUrl': downloadUrl,
        'isDownloaded': isDownloaded,
      };

  factory RemoteFontItem.fromJson(Map<String, dynamic> json) => RemoteFontItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        family: json['family'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        isDownloaded: json['isDownloaded'] as bool? ?? false,
      );
}

class RemoteElementItem {
  const RemoteElementItem({
    required this.id,
    required this.name,
    required this.svgContent,
    required this.category,
    this.downloadUrl = '',
  });

  final String id;
  final String name;
  final String svgContent;
  final String category;
  final String downloadUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'svgContent': svgContent,
        'category': category,
        'downloadUrl': downloadUrl,
      };

  factory RemoteElementItem.fromJson(Map<String, dynamic> json) => RemoteElementItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        svgContent: json['svgContent'] as String? ?? '',
        category: json['category'] as String? ?? 'General',
        downloadUrl: json['downloadUrl'] as String? ?? '',
      );
}

class RemoteAnimationItem {
  const RemoteAnimationItem({
    required this.id,
    required this.name,
    required this.type,
    required this.durationMs,
    this.description = '',
  });

  final String id;
  final String name;
  final String type;
  final int durationMs;
  final String description;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'durationMs': durationMs,
        'description': description,
      };

  factory RemoteAnimationItem.fromJson(Map<String, dynamic> json) => RemoteAnimationItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'in',
        durationMs: json['durationMs'] as int? ?? 1000,
        description: json['description'] as String? ?? '',
      );
}

class FirebaseAssetService {
  FirebaseAssetService._internal();
  static final FirebaseAssetService instance = FirebaseAssetService._internal();

  FirebaseFirestore? get _db {
    if (FirebaseService.instance.isInitialized) {
      try {
        return FirebaseFirestore.instance;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Effects
  // --------------------------------------------------------------------------

  Future<List<ShaderEffect>> fetchRemoteEffects() async {
    final firestore = _db;
    if (firestore != null) {
      try {
        final snapshot = await firestore.collection('effects').get();
        if (snapshot.docs.isNotEmpty) {
          final effects = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return ShaderEffect.fromJson(data);
          }).toList();
          AppLogger.info('Fetched ${effects.length} remote effects from Firebase', tag: 'FirebaseAssetService');
          return effects;
        }
      } catch (e) {
        AppLogger.warning('Firebase effects fetch error: $e. Using local defaults.', tag: 'FirebaseAssetService');
      }
    }

    // Default remote effect catalogue fallback
    return <ShaderEffect>[
      const ShaderEffect(
        id: 'fx_fb_cyberpulse',
        name: 'Cyber Pulse',
        description: 'Futuristic glowing cybernetic pulse grid',
        category: ShaderEffectCategory.neon,
        type: EffectType.downloadable,
        author: 'Firebase Cloud',
        isDownloaded: false,
        shaderSource: '''#version 300 es
precision mediump float;
in vec2 v_texCoord;
out vec4 fragColor;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_intensity;
void main() {
    vec4 color = texture(u_texture, v_texCoord);
    float glow = sin(v_texCoord.y * 30.0 + u_time * 5.0) * 0.5 + 0.5;
    vec3 cyan = vec3(0.0, 0.9, 1.0) * glow * u_intensity;
    fragColor = vec4(mix(color.rgb, cyan, 0.4), color.a);
}''',
      ),
      const ShaderEffect(
        id: 'fx_fb_aurora',
        name: 'Aurora Borealis',
        description: 'Ethereal northern lights color drift',
        category: ShaderEffectCategory.glow,
        type: EffectType.downloadable,
        author: 'Firebase Cloud',
        isDownloaded: false,
        shaderSource: '''#version 300 es
precision mediump float;
in vec2 v_texCoord;
out vec4 fragColor;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_intensity;
void main() {
    vec4 color = texture(u_texture, v_texCoord);
    vec3 aurora = vec3(0.2, 0.8, 0.5) * sin(v_texCoord.x * 10.0 + u_time * 2.0);
    fragColor = vec4(color.rgb + aurora * u_intensity, color.a);
}''',
      ),
    ];
  }

  Future<ShaderEffect> downloadEffect(ShaderEffect effect) async {
    final downloaded = effect.copyWith(isDownloaded: true);
    await ShaderDatabaseService.instance.saveDownloadedEffect(
      downloaded,
      effect.shaderSource.isNotEmpty ? effect.shaderSource : '// Firebase Shader: ${effect.name}',
    );
    AppLogger.info('Downloaded effect: ${effect.name}', tag: 'FirebaseAssetService');
    return downloaded;
  }

  // --------------------------------------------------------------------------
  // Fonts
  // --------------------------------------------------------------------------

  Future<List<RemoteFontItem>> fetchRemoteFonts() async {
    final firestore = _db;
    if (firestore != null) {
      try {
        final snapshot = await firestore.collection('fonts').get();
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return RemoteFontItem.fromJson(data);
          }).toList();
        }
      } catch (e) {
        AppLogger.warning('Firebase fonts fetch error: $e', tag: 'FirebaseAssetService');
      }
    }

    return const <RemoteFontItem>[
      RemoteFontItem(
        id: 'font_fb_bengali',
        name: 'Hind Siliguri Bold',
        family: 'Hind Siliguri',
        downloadUrl: 'https://fonts.gstatic.com/s/hindsiliguri/v12/ij2243f9a9412948-HindSiliguri-Bold.ttf',
      ),
      RemoteFontItem(
        id: 'font_fb_oswald',
        name: 'Oswald Bold',
        family: 'Oswald',
        downloadUrl: 'https://fonts.gstatic.com/s/oswald/v49/TK3iWkUHHAIjg752GT8G.ttf',
      ),
      RemoteFontItem(
        id: 'font_fb_bebas',
        name: 'Bebas Neue',
        family: 'Bebas Neue',
        downloadUrl: 'https://fonts.gstatic.com/s/bebasneue/v9/JTUSjIg1_i6t8kCHKm45xW4.ttf',
      ),
    ];
  }

  // --------------------------------------------------------------------------
  // Elements
  // --------------------------------------------------------------------------

  Future<List<RemoteElementItem>> fetchRemoteElements() async {
    final firestore = _db;
    if (firestore != null) {
      try {
        final snapshot = await firestore.collection('elements').get();
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return RemoteElementItem.fromJson(data);
          }).toList();
        }
      } catch (e) {
        AppLogger.warning('Firebase elements fetch error: $e', tag: 'FirebaseAssetService');
      }
    }

    return const <RemoteElementItem>[
      RemoteElementItem(
        id: 'elem_fb_starburst',
        name: 'Star Burst',
        category: 'Badges',
        svgContent: '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><polygon points="50,0 63,35 100,50 63,65 50,100 37,65 0,50 37,35" fill="#00E5FF"/></svg>''',
      ),
      RemoteElementItem(
        id: 'elem_fb_badge_sale',
        name: 'Neon Frame',
        category: 'Frames',
        svgContent: '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="5" y="5" width="90" height="90" rx="15" fill="none" stroke="#FF2D55" stroke-width="8"/></svg>''',
      ),
      RemoteElementItem(
        id: 'elem_fb_crown',
        name: 'Golden Crown',
        category: 'Stickers',
        svgContent: '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><polygon points="10,80 20,30 40,60 50,20 60,60 80,30 90,80" fill="#FFCC00"/></svg>''',
      ),
    ];
  }

  // --------------------------------------------------------------------------
  // Animations
  // --------------------------------------------------------------------------

  Future<List<RemoteAnimationItem>> fetchRemoteAnimations() async {
    final firestore = _db;
    if (firestore != null) {
      try {
        final snapshot = await firestore.collection('animations').get();
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return RemoteAnimationItem.fromJson(data);
          }).toList();
        }
      } catch (e) {
        AppLogger.warning('Firebase animations fetch error: $e', tag: 'FirebaseAssetService');
      }
    }

    return const <RemoteAnimationItem>[
      RemoteAnimationItem(id: 'anim_fb_zoom_bounce', name: 'Zoom & Bounce', type: 'in', durationMs: 800),
      RemoteAnimationItem(id: 'anim_fb_spin_fade', name: 'Spin Fade Out', type: 'out', durationMs: 1000),
      RemoteAnimationItem(id: 'anim_fb_glitch_flash', name: 'Glitch Flash In', type: 'in', durationMs: 600),
    ];
  }
}
