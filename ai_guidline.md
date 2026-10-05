
# CRITICAL ISSUES TO FIX (Priority Order)

## PHASE 1: SECURITY & BUILD CONFIGURATION (Week 1)
### Issue 1.1: Signing Configuration for Release
Current Problem:
- android/app/build.gradle.kts uses debug signing for release builds
- Line 43: signingConfig = signingConfigs.getByName("debug")
- This prevents Google Play Store submission

Required Output:
1. Generate keystore file generation guide with keytool command
2. Update android/app/build.gradle.kts with release signing config
3. Add environment variable setup for CI/CD (GitHub Actions)
4. Update .github/workflows/build_apk.yml to use signing credentials
5. Add gradle.properties template for local development

### Issue 1.2: Application ID & Versioning
Current Problem:
- applicationId = "com.example.flutter_video_editor" (placeholder)
- versionCode/versionName not properly configured

Required Output:
1. Change to unique applicationId: "com.motiongr.videoedit"
2. Setup versionCode (1) and versionName (1.0.0) with automation
3. Create version management system (pubspec.yaml synchronization)
4. Add build flavor support (dev, staging, production)

## PHASE 2: ACTUAL VIDEO EXPORT IMPLEMENTATION (Weeks 2-4)

### Issue 2.1: Replace Mock Export with Real Video Rendering (Android)
Current Problem:
- lib/features/export/services/export_service.dart (Lines 108-149) has FAKE implementation
- Mock creates text file instead of actual video: 
  ```dart
  await tempFile.writeAsString('Rendered video file simulation data');
  ```
- No actual FFmpeg or MediaCodec integration

Required Dart Code Changes:
1. Update lib/features/export/services/export_service.dart:
   - Replace mock exportTimeline() with real platform channel calls
   - Add timeout handling and stream error recovery
   - Implement proper progress tracking
   - Add FFmpeg fallback support

2. Update lib/features/export/models/timeline_dto.dart:
   - Ensure all clip properties serialize correctly (resolution, fps, bitrate)
   - Add validation for export settings

3. Update lib/features/export/controllers/export_controller.dart:
   - Add retry logic for failed exports
   - Implement cancelExport() with proper cleanup
   - Add memory management for large projects

Required Kotlin Implementation (Android Native):
1. Complete android/app/src/main/kotlin/com/example/flutter_video_editor/export/ExportPlugin.kt:
   - Implement MethodChannel handler for 'export' method
   - Implement 'probe', 'thumbnails', 'waveform' methods
   - Handle platform exceptions and timeouts

2. Complete android/app/src/main/kotlin/com/example/flutter_video_editor/export/CompositionBuilder.kt:
   - Parse TimelineDto JSON from Dart
   - Build Media3 Composition with clips
   - Handle video, audio, image, text, effects layers
   - Support video effects (warm, cinematic, noir, vibrant, vintage, glitch, blur)

3. Complete android/app/src/main/kotlin/com/example/flutter_video_editor/export/TimelineParser.kt:
   - Convert Dart timeline JSON to Kotlin data structures
   - Validate clip timings and overlaps
   - Handle aspect ratio conversions

4. Complete android/app/src/main/kotlin/com/example/flutter_video_editor/export/ExportForegroundService.kt:
   - Run video rendering in foreground service
   - Provide progress updates via EventChannel
   - Handle user cancellation gracefully
   - Clean up resources on completion/error

5. Add new: FFmpegWrapper.kt
   - Integrate ffmpeg-kit library OR MediaCodec implementation
   - Handle multiple video codecs (H.264, H.265, VP9)
   - Support various audio codecs

6. Add new: OverlayRenderer.kt enhancements
   - Support text rendering with animations
   - Support sticker positioning and scaling
   - Support drawing strokes overlay

Required gradle Dependencies (android/app/build.gradle.kts):
```kotlin
// Add these
implementation("com.arthenica:ffmpeg-kit-full:6.0")  // or use Media3
implementation("androidx.work:work-runtime-ktx:2.8.1")  // for background export
```

### Issue 2.2: Video Export for iOS
Current Problem:
- ios/Runner/Export/ExportPlugin.swift is EMPTY/STUB
- ios/Runner/Export/CompositionBuilder.swift is EMPTY/STUB
- No iOS video rendering capability

Required Swift Implementation:
1. Complete ios/Runner/Export/ExportPlugin.swift:
   - Implement MethodChannel handler for 'export' method
   - Implement 'probe', 'thumbnails', 'waveform' methods

2. Complete ios/Runner/Export/CompositionBuilder.swift:
   - Build AVFoundation composition from timeline JSON
   - Support same effects as Android version

3. Implement ios/Runner/Export/CustomVideoCompositor.swift:
   - Handle video compositing with effects
   - Support color grading settings

4. Update ios/Runner/Export/TimelineParser.swift:
   - Complete timeline parsing logic

### Issue 2.3: Export Gradle Dependencies Update
Current Problem:
- Media3 dependencies present but incomplete
- Missing FFmpeg integration

Required Changes:
- Keep Media3 but add ffmpeg-kit-full
- Update Gradle to latest compatible versions
- Add build variant configuration

---

## PHASE 3: PERMISSIONS & RUNTIME SAFETY (Week 2)

### Issue 3.1: Android Permissions Runtime Handling
Current Problem:
- android/app/src/main/AndroidManifest.xml declares permissions but NO runtime checks
- Android 13+ requires READ_MEDIA_VIDEO, READ_MEDIA_AUDIO, READ_MEDIA_IMAGES at runtime
- No Storage Access Framework (SAF) support

Required Implementation:
1. Add to pubspec.yaml:
   ```yaml
   permission_handler: ^11.5.0
   ```

2. Create lib/core/services/permission_service.dart:
   - Check and request media reading permissions
   - Handle Android 13+ scoped storage
   - Implement SAF for file access
   - Provide user-friendly error messages

3. Add permission checks before:
   - Media picker usage (MediaPickerPage)
   - Export operations
   - Project save/load

4. Update ios/Runner/Info.plist:
   - Add NSPhotoLibraryUsageDescription
   - Add NSCameraUsageDescription
   - Add NSMicrophoneUsageDescription

---

## PHASE 4: DATA PERSISTENCE & PROJECT SAVE/LOAD (Weeks 3-4)

### Issue 4.1: Local Database Setup
Current Problem:
- lib/core/models/project_model.dart has NO serialization
- No database for saving/loading projects
- All work lost when app closes

Required Implementation:
1. Add to pubspec.yaml:
   ```yaml
   isar: ^3.1.0  # or hive: ^2.2.0
   path_provider: ^2.1.6
   ```

2. Create lib/core/database/project_database.dart:
   - Initialize Isar collections for Project, TimelineClip, ExportSettings
   - Implement CRUD operations
   - Add query methods (list, get by ID, search by name)

3. Update lib/core/models/project_model.dart:
   - Add @Collection annotations if using Isar
   - Make classes serializable
   - Add fromJson/toJson methods

4. Create lib/features/projects/services/project_service.dart:
   - Save active project on editor changes
   - Auto-save every 30 seconds
   - Provide project history/versioning

5. Update lib/features/projects/pages/home_page.dart:
   - Show saved projects list from database
   - Display project thumbnails
   - Allow project deletion/renaming

### Issue 4.2: Auto-Save & Crash Recovery
Required Implementation:
1. Create lib/core/services/autosave_service.dart:
   - Save project state every 30 seconds
   - Detect app crashes on restart
   - Offer recovery dialog with project versions

---

## PHASE 5: ERROR HANDLING & MONITORING (Week 4)

### Issue 5.1: Crash Reporting Setup
Current Problem:
- No error tracking system
- No visibility into production crashes

Required Implementation:
1. Add to pubspec.yaml:
   ```yaml
   firebase_crashlytics: ^3.4.0
   firebase_core: ^2.24.0
   # OR
   sentry_flutter: ^7.8.0
   ```

2. Update lib/main.dart:
   - Initialize Firebase/Sentry
   - Setup global error handlers
   - Wrap runApp with error boundaries

3. Create lib/core/services/crash_service.dart:
   - Log exceptions and stack traces
   - Attach device/app context
   - Track user sessions

### Issue 5.2: Structured Logging System
Required Implementation:
1. Create lib/core/logger/app_logger.dart:
   - Log levels (debug, info, warn, error)
   - File logging for offline debugging
   - Console logging with colors
   - Remote logging to API endpoint

2. Replace all print() statements with AppLogger
3. Add file-based log storage for last 7 days

### Issue 5.3: Error Recovery & User-Friendly Messages
Required Implementation:
1. Create lib/core/error/app_exceptions.dart:
   - Define custom exceptions (ExportException, PermissionException, StorageException)
   - Add error codes and user messages

2. Create lib/core/error/error_handler.dart:
   - Convert exceptions to user-friendly dialogs
   - Provide retry mechanisms

3. Update all controllers:
   - Wrap async operations in try-catch
   - Show error dialogs
   - Implement retry logic

---

## PHASE 6: STATE MANAGEMENT IMPROVEMENTS (Week 3)

### Issue 6.1: EditorController Stability
Current Problem:
- lib/features/editor/controllers/editor_controller.dart has NO error handling
- No null safety checks
- Risk of memory leaks

Required Implementation:
1. Add comprehensive null checks and validation
2. Implement resource cleanup in dispose()
3. Add error logging throughout
4. Implement undo/redo with memory limits
5. Add clip validation before render

---

## PHASE 7: BUILD PIPELINE & CI/CD (Weeks 1-2)

### Issue 7.1: GitHub Actions Workflow Enhancement
Current Problem:
- .github/workflows/build_apk.yml basic, missing signing and testing

Required Updates:
1. Add secret management:
   - KEYSTORE_BASE64 (base64 encoded keystore)
   - KEY_ALIAS, KEY_PASSWORD, STORE_PASSWORD
   - Firebase credentials for Crashlytics

2. Add build matrix for multiple Android versions (API 21, 28, 32, 33, 34)

3. Add TestFlight/App Store Connect for iOS builds

4. Add code analysis steps:
   - flutter analyze
   - dart fix --dry-run
   - dart format --set-exit-if-changed .

5. Add test coverage reporting

6. Add automatic version bumping

---

## PHASE 8: TESTING & QUALITY ASSURANCE (Weeks 5-6)

### Issue 8.1: Unit Test Expansion
Required Tests:
1. test/export_controller_test.dart - Expand with real export scenarios
2. test/project_persistence_test.dart - NEW: Database operations
3. test/export_service_test.dart - NEW: Mock Android/iOS export
4. test/permissions_service_test.dart - NEW: Permission handling
5. test/error_handler_test.dart - NEW: Error recovery

### Issue 8.2: Widget Tests
Required Tests:
1. test/features/editor/pages/editor_page_test.dart
2. test/features/projects/pages/home_page_test.dart
3. test/features/export/widgets/export_dialog_test.dart

### Issue 8.3: Integration Tests
Required Tests:
1. integration_test/export_flow_test.dart - Full export workflow
2. integration_test/project_workflow_test.dart - Create, edit, save, load, export

---

## PHASE 9: APP STORE COMPLIANCE & SUBMISSION (Week 7)

### Issue 9.1: Google Play Console Setup
Required:
1. Create Google Play Developer account
2. Setup app listing with:
   - Screenshots (minimum 2, recommended 8)
   - Description (in English and Bengali)
   - Privacy policy
   - Contact email
3. Configure content rating questionnaire
4. Set up pricing and distribution
5. Create closed beta track for testing

### Issue 9.2: App Store (iOS) Setup
Required:
1. Create Apple Developer account
2. Setup TestFlight for beta testing
3. Create app listing on App Store Connect
4. Configure screenshots, descriptions
5. Setup App Store review guidelines compliance

---

## CURRENT CODE STRUCTURE ANALYSIS

### ✅ What's Already Good:
1. Dart project structure (lib/, test/, pubspec.yaml)
2. Provider state management
3. Rich data models (Project, TimelineClip, ExportSettings)
4. Timeline UI with multi-track support
5. Theme system (AppColors, AppTheme)
6. Feature-based folder organization
7. Android native plugin architecture

### ❌ What Needs Fixing:
1. Export system (MOCK implementation)
2. Data persistence (NO database)
3. Permissions (NO runtime checks)
4. Error handling (MINIMAL)
5. iOS implementation (EMPTY)
6. Logging & monitoring (NONE)
7. Release signing (DEBUG key used)
8. Tests (BASIC, not comprehensive)

---

## DELIVERABLES CHECKLIST

### Dart/Flutter Files to Create/Update:
- [ ] lib/core/database/project_database.dart (NEW)
- [ ] lib/core/services/permission_service.dart (NEW)
- [ ] lib/core/services/autosave_service.dart (NEW)
- [ ] lib/core/services/crash_service.dart (NEW)
- [ ] lib/core/logger/app_logger.dart (NEW)
- [ ] lib/core/error/app_exceptions.dart (NEW)
- [ ] lib/core/error/error_handler.dart (NEW)
- [ ] lib/features/export/services/export_service.dart (UPDATE)
- [ ] lib/features/export/controllers/export_controller.dart (UPDATE)
- [ ] lib/features/export/models/timeline_dto.dart (UPDATE)
- [ ] lib/features/projects/services/project_service.dart (NEW)
- [ ] lib/features/editor/controllers/editor_controller.dart (UPDATE)
- [ ] lib/main.dart (UPDATE - add error handling)
- [ ] pubspec.yaml (UPDATE - add dependencies)

### Android Kotlin Files to Create/Update:
- [ ] android/app/build.gradle.kts (UPDATE - signing config)
- [ ] android/app/src/main/kotlin/com/example/flutter_video_editor/export/ExportPlugin.kt (COMPLETE)
- [ ] android/app/src/main/kotlin/com/example/flutter_video_editor/export/CompositionBuilder.kt (COMPLETE)
- [ ] android/app/src/main/kotlin/com/example/flutter_video_editor/export/TimelineParser.kt (COMPLETE)
- [ ] android/app/src/main/kotlin/com/example/flutter_video_editor/export/ExportForegroundService.kt (COMPLETE)
- [ ] android/app/src/main/kotlin/com/example/flutter_video_editor/export/FFmpegWrapper.kt (NEW)
- [ ] android/app/src/main/kotlin/com/example/flutter_video_editor/MainActivity.kt (UPDATE - error handling)

### iOS Swift Files to Create/Update:
- [ ] ios/Runner/Export/ExportPlugin.swift (COMPLETE)
- [ ] ios/Runner/Export/CompositionBuilder.swift (COMPLETE)
- [ ] ios/Runner/Export/CustomVideoCompositor.swift (COMPLETE)
- [ ] ios/Runner/Export/TimelineParser.swift (COMPLETE)
- [ ] ios/Runner/Info.plist (UPDATE - permissions)

### Configuration Files:
- [ ] android/app/build.gradle.kts (SIGNING)
- [ ] .github/workflows/build_apk.yml (ENHANCE with signing & testing)
- [ ] .github/workflows/build_ios.yml (NEW)
- [ ] gradle.properties (TEMPLATE)
- [ ] ios/Podfile (UPDATE if needed)

### Test Files:
- [ ] test/export_controller_test.dart (EXPAND)
- [ ] test/project_persistence_test.dart (NEW)
- [ ] test/export_service_test.dart (NEW)
- [ ] test/permissions_service_test.dart (NEW)
- [ ] test/error_handler_test.dart (NEW)
- [ ] integration_test/export_flow_test.dart (NEW)
- [ ] integration_test/project_workflow_test.dart (NEW)

### Documentation Files:
- [ ] SETUP.md - Development setup guide
- [ ] RELEASE.md - Release procedure
- [ ] ARCHITECTURE.md - Technical architecture
- [ ] PRIVACY.md - Privacy policy for app stores
- [ ] BUILD_GUIDE.md - Step-by-step build instructions

---

## TECHNICAL SPECIFICATIONS

### Export Video Requirements:
- **Formats:** MP4 (H.264), MOV, GIF
- **Resolutions:** 720p, 1080p, 4K
- **Frame Rates:** 24, 30, 60 fps
- **Bitrates:** Low (4 Mbps), Medium (8 Mbps), High (16 Mbps), Ultra (25 Mbps)
- **Aspect Ratios:** 9:16, 16:9, 1:1, 4:5, Original
- **Effects:** Warm, Cinematic, Noir, Vibrant, Vintage, Glitch, Blur
- **Supported Tracks:** Video, Audio, Image, Text, Stickers, Drawings

### Performance Targets:
- **Timeline Preview:** 60 FPS smooth scrolling
- **Export Speed:** Real-time or faster (depends on device)
- **Memory Usage:** < 500 MB for projects < 10 min
- **App Launch Time:** < 2 seconds
- **Project Load Time:** < 1 second

### Target Platforms:
- **Android:** API 21 (Android 5.0) - 34 (Android 14)
- **iOS:** iOS 12.0+
- **Device Types:** Phones, Tablets

---

## IMPLEMENTATION GUIDELINES

### Dart/Flutter:
- Use null safety (enable strict mode)
- Follow Flutter style guide (avoid lint warnings)
- Use const constructors where possible
- Implement proper dispose() methods
- Handle platform exceptions gracefully

### Kotlin (Android):
- Use coroutines for async operations
- Implement proper lifecycle management
- Handle permissions correctly
- Use strong typing
- Add comprehensive logging

### Swift (iOS):
- Use modern Swift (5.7+)
- Implement proper memory management
- Handle background execution
- Add proper error handling

### All Code:
- Add JSDoc/documentation comments
- Write type-safe code
- Avoid code duplication
- Follow DRY principles
- Add error handling at every boundary

---

## DEPENDENCIES TO ADD

### pubspec.yaml:
```yaml
# Database
isar: ^3.1.0
isar_flutter_libs: ^3.1.0

# Permissions
permission_handler: ^11.5.0

# Crash Reporting (choose one)
firebase_crashlytics: ^3.4.0
firebase_core: ^2.24.0
# OR
sentry_flutter: ^7.8.0

# Logging
logger: ^2.0.0

# Local storage
path_provider: ^2.1.6
shared_preferences: ^2.2.0

# Testing
mockito: ^5.4.4
mocktail: ^1.0.0
```

### Android build.gradle.kts:
```kotlin
implementation("com.arthenica:ffmpeg-kit-full:6.0")
implementation("androidx.work:work-runtime-ktx:2.8.1")
implementation("androidx.media3:media3-transformer:1.5.1")
```
---

