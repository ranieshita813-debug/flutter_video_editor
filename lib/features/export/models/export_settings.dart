import 'package:flutter_video_editor/core/models/project_model.dart';

class ExportSettings {
  const ExportSettings({
    this.resolution = ExportResolution.res1080p,
    this.fps = 30,
    this.quality = ExportQuality.high,
    this.format = ExportFormat.mp4,
    this.codec = 'h264',
    this.audioBitrateKbps = 192,
    this.customBitrateMbps,
  });

  final ExportResolution resolution;
  final int fps;
  final ExportQuality quality;
  final ExportFormat format;
  final String codec; // 'h264' or 'hevc'
  final int audioBitrateKbps;
  final double? customBitrateMbps;

  int get width => resolution.width;
  int get height => resolution.height;

  double get effectiveBitrateMbps => customBitrateMbps ?? quality.bitrateMbps;
  int get bitrateKbps => (effectiveBitrateMbps * 1000).toInt();

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'width': width,
      'height': height,
      'fps': fps,
      'quality': quality.name,
      'format': format.name,
      'codec': codec,
      'bitrateKbps': bitrateKbps,
      'audioBitrateKbps': audioBitrateKbps,
    };
  }

  factory ExportSettings.fromJson(Map<String, dynamic> json) {
    final resLabel = json['width'] == 3840 ? ExportResolution.res4k : (json['width'] == 1280 ? ExportResolution.res720p : ExportResolution.res1080p);
    return ExportSettings(
      resolution: resLabel,
      fps: json['fps'] as int? ?? 30,
      codec: json['codec'] as String? ?? 'h264',
      audioBitrateKbps: json['audioBitrateKbps'] as int? ?? 192,
      customBitrateMbps: json['bitrateKbps'] != null ? (json['bitrateKbps'] as num).toDouble() / 1000.0 : null,
    );
  }

  ExportSettings copyWith({
    ExportResolution? resolution,
    int? fps,
    ExportQuality? quality,
    ExportFormat? format,
    String? codec,
    int? audioBitrateKbps,
    double? customBitrateMbps,
  }) {
    return ExportSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      quality: quality ?? this.quality,
      format: format ?? this.format,
      codec: codec ?? this.codec,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      customBitrateMbps: customBitrateMbps ?? this.customBitrateMbps,
    );
  }
}
