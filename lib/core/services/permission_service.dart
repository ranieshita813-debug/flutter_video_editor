import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  /// Requests permissions for media library access (videos/photos/audio).
  Future<bool> requestMediaPermissions() async {
    if (Platform.isAndroid) {
      // Android 13+ (API 33+) requires granular media permissions
      final videos = await Permission.videos.request();
      final photos = await Permission.photos.request();
      final audio = await Permission.audio.request();

      if (videos.isGranted || photos.isGranted || audio.isGranted) {
        return true;
      }

      // Fallback for Android 12 and below
      final storage = await Permission.storage.request();
      return storage.isGranted;
    } else if (Platform.isIOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }
    return true;
  }

  /// Requests camera and microphone permissions for recording media.
  Future<bool> requestCameraAndMicrophonePermissions() async {
    final camera = await Permission.camera.request();
    final microphone = await Permission.microphone.request();
    return camera.isGranted && microphone.isGranted;
  }

  /// Checks whether media permission is granted without prompting.
  Future<bool> hasMediaPermissions() async {
    if (Platform.isAndroid) {
      final videos = await Permission.videos.status;
      final photos = await Permission.photos.status;
      final storage = await Permission.storage.status;
      return videos.isGranted || photos.isGranted || storage.isGranted;
    } else if (Platform.isIOS) {
      final photos = await Permission.photos.status;
      return photos.isGranted || photos.isLimited;
    }
    return true;
  }

  /// Opens app settings if permissions are permanently denied.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
