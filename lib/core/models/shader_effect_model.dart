import 'package:flutter/material.dart';

enum EffectType {
  builtIn,
  downloadable,
  custom,
}

enum ShaderEffectCategory {
  all('All'),
  glow('Glow & Neon'),
  blur('Blur & Focus'),
  cinematic('Cinematic'),
  vintage('Vintage & Retro'),
  noir('Noir & Dark'),
  neon('Neon & Cyber'),
  glitch('Glitch & Scanlines'),
  bloom('Bloom'),
  lightLeak('Light Leak'),
  distortion('Distortion'),
  colorStyle('Color & Mood');

  const ShaderEffectCategory(this.displayName);
  final String displayName;
}

enum ParameterType {
  float,
  integer,
  color,
  position,
  boolean,
  choice,
}

class ShaderParameter {
  const ShaderParameter({
    required this.id,
    required this.name,
    required this.label,
    required this.type,
    required this.value,
    required this.defaultValue,
    this.min = 0.0,
    this.max = 1.0,
    this.options = const <String>[],
  });

  final String id;
  final String name;
  final String label;
  final ParameterType type;
  final dynamic value;
  final dynamic defaultValue;
  final double min;
  final double max;
  final List<String> options;

  double get doubleValue {
    if (value is num) return (value as num).toDouble();
    if (defaultValue is num) return (defaultValue as num).toDouble();
    return min;
  }

  int get intValue {
    if (value is int) return value as int;
    if (value is num) return (value as num).toInt();
    if (defaultValue is num) return (defaultValue as num).toInt();
    return min.toInt();
  }

  bool get boolValue {
    if (value is bool) return value as bool;
    if (defaultValue is bool) return defaultValue as bool;
    return false;
  }

  Color get colorValue {
    if (value is Color) return value as Color;
    if (value is int) return Color(value as int);
    if (defaultValue is Color) return defaultValue as Color;
    if (defaultValue is int) return Color(defaultValue as int);
    return Colors.white;
  }

  Offset get positionValue {
    if (value is Offset) return value as Offset;
    if (value is Map) {
      final m = Map<String, dynamic>.from(value as Map);
      return Offset(
        (m['x'] as num?)?.toDouble() ?? 0.0,
        (m['y'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return Offset.zero;
  }

  ShaderParameter copyWith({
    String? id,
    String? name,
    String? label,
    ParameterType? type,
    dynamic value,
    dynamic defaultValue,
    double? min,
    double? max,
    List<String>? options,
  }) {
    return ShaderParameter(
      id: id ?? this.id,
      name: name ?? this.name,
      label: label ?? this.label,
      type: type ?? this.type,
      value: value ?? this.value,
      defaultValue: defaultValue ?? this.defaultValue,
      min: min ?? this.min,
      max: max ?? this.max,
      options: options ?? this.options,
    );
  }

  Map<String, dynamic> toJson() {
    dynamic serializedValue = value;
    dynamic serializedDefault = defaultValue;

    if (value is Color) {
      serializedValue = (value as Color).toARGB32();
    } else if (value is Offset) {
      serializedValue = <String, double>{
        'x': (value as Offset).dx,
        'y': (value as Offset).dy
      };
    }

    if (defaultValue is Color) {
      serializedDefault = (defaultValue as Color).toARGB32();
    } else if (defaultValue is Offset) {
      serializedDefault = <String, double>{
        'x': (defaultValue as Offset).dx,
        'y': (defaultValue as Offset).dy
      };
    }

    return <String, dynamic>{
      'id': id,
      'name': name,
      'label': label,
      'type': type.name,
      'value': serializedValue,
      'defaultValue': serializedDefault,
      'min': min,
      'max': max,
      'options': options,
    };
  }

  factory ShaderParameter.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'float';
    final type = ParameterType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ParameterType.float,
    );

    dynamic val = json['value'];
    dynamic defVal = json['defaultValue'];

    if (type == ParameterType.color) {
      if (val is int) val = Color(val);
      if (defVal is int) defVal = Color(defVal);
    } else if (type == ParameterType.position) {
      if (val is Map) {
        val = Offset(
          (val['x'] as num?)?.toDouble() ?? 0.0,
          (val['y'] as num?)?.toDouble() ?? 0.0,
        );
      }
      if (defVal is Map) {
        defVal = Offset(
          (defVal['x'] as num?)?.toDouble() ?? 0.0,
          (defVal['y'] as num?)?.toDouble() ?? 0.0,
        );
      }
    }

    return ShaderParameter(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: type,
      value: val ?? 0.0,
      defaultValue: defVal ?? 0.0,
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 1.0,
      options: (json['options'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
    );
  }
}

class ShaderEffect {
  const ShaderEffect({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.type = EffectType.builtIn,
    this.thumbnailUrl = '',
    this.parameters = const <ShaderParameter>[],
    this.shaderSource = '',
    this.localCachePath,
    this.isFavorite = false,
    this.isDownloaded = true,
    this.author = 'motionGr',
    this.sizeBytes = 0,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final ShaderEffectCategory category;
  final EffectType type;
  final String thumbnailUrl;
  final List<ShaderParameter> parameters;
  final String shaderSource;
  final String? localCachePath;
  final bool isFavorite;
  final bool isDownloaded;
  final String author;
  final int sizeBytes;
  final DateTime? updatedAt;

  ShaderEffect copyWith({
    String? id,
    String? name,
    String? description,
    ShaderEffectCategory? category,
    EffectType? type,
    String? thumbnailUrl,
    List<ShaderParameter>? parameters,
    String? shaderSource,
    String? localCachePath,
    bool? isFavorite,
    bool? isDownloaded,
    String? author,
    int? sizeBytes,
    DateTime? updatedAt,
  }) {
    return ShaderEffect(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      type: type ?? this.type,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      parameters: parameters ?? this.parameters,
      shaderSource: shaderSource ?? this.shaderSource,
      localCachePath: localCachePath ?? this.localCachePath,
      isFavorite: isFavorite ?? this.isFavorite,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      author: author ?? this.author,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'category': category.name,
      'type': type.name,
      'thumbnailUrl': thumbnailUrl,
      'parameters': parameters.map((p) => p.toJson()).toList(),
      'shaderSource': shaderSource,
      'localCachePath': localCachePath,
      'isFavorite': isFavorite,
      'isDownloaded': isDownloaded,
      'author': author,
      'sizeBytes': sizeBytes,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory ShaderEffect.fromJson(Map<String, dynamic> json) {
    return ShaderEffect(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: ShaderEffectCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => ShaderEffectCategory.glow,
      ),
      type: EffectType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => EffectType.builtIn,
      ),
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      parameters: (json['parameters'] as List<dynamic>?)
              ?.map((e) => ShaderParameter.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const <ShaderParameter>[],
      shaderSource: json['shaderSource'] as String? ?? '',
      localCachePath: json['localCachePath'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isDownloaded: json['isDownloaded'] as bool? ?? true,
      author: json['author'] as String? ?? 'motionGr',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
