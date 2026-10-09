# Flutter Video Editor - Tasks Breakdown

## Project Overview
**Repository**: `ranieshita813-debug/flutter_video_editor`  
**Description**: Advanced Android video editor foundation built with Flutter, inspired by CapCut and pro NLE tools  
**Language Composition**: Dart (85.9%), Kotlin (10.3%), Swift (2.6%), C++ (0.7%), GLSL (0.2%), Objective-C (0.2%)

---

## Task 1: SVG Logo & Watermark System
**Priority**: High | **Status**: In Progress (PR #35)

### Objectives
- ✅ Remove all text-based logos from the UI
- ✅ Use **SVG logo only** across all pages
- ✅ Implement SVG watermark on canvas
- Ensure watermark size is kept minimal (2-5% of canvas)

### Affected Pages/Components
- `lib/pages/splash_screen.dart` - Use SVG logo instead of text
- `lib/pages/auth_page.dart` - Update auth header with SVG
- `lib/pages/home_page.dart` - Update home header branding
- `lib/pages/editor_page.dart` - Add watermark to video preview canvas

### SVG Assets Required
- Location: `assets/logo.svg` (already declared in pubspec.yaml)
- Implementation: Use `SvgPicture.asset()` from `flutter_svg` package

### Code Changes
```dart
// Replace TextLogo with SVG
SvgPicture.asset(
  'assets/logo.svg',
  width: 40, // Adjust based on watermark need
  height: 40,
  fit: BoxFit.contain,
)
```

### Watermark Integration
- Render on canvas at 0.03 opacity (very subtle)
- Position: Bottom-right corner of video preview
- Size: 80-120px max
- Apply transform for subtle rotation if needed

---

## Task 2: Button Color Scheme Overhaul
**Priority**: High | **Status**: Pending

### Objectives
- ✅ Remove all gradient color buttons
- ✅ Use **white buttons** for all actions
- Apply consistent white styling across toolbar and sheets

### Affected Components
- All buttons in `lib/pages/editor_page.dart`
- Toolbar buttons in `lib/widgets/toolbar/`
- Tool sheet headers and action buttons
- Export/Save buttons throughout app

### Design Token Updates
Create/Update `lib/core/tokens/editor_tokens.dart`:
```dart
class EditorTokens {
  // Colors
  static const Color buttonBackground = Colors.white;
  static const Color buttonForeground = Color(0xFF1A1A1A);
  static const Color buttonBorder = Color(0xFFE0E0E0);
  
  // Button styles
  static ButtonStyle whiteButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Color(0xFF1A1A1A),
    elevation: 0,
    side: BorderSide(color: Color(0xFFE0E0E0), width: 1),
  );
}
```

### Implementation Pattern
```dart
// Before
ElevatedButton(
  style: ElevatedButton.styleFrom(
    gradient: LinearGradient(...),
  ),
  child: Text('Export'),
  onPressed: () {},
)

// After
ElevatedButton(
  style: EditorTokens.whiteButtonStyle,
  child: Text('Export'),
  onPressed: () {},
)
```

---

## Task 3: App Icon Setup
**Priority**: High | **Status**: Pending

### Objectives
- ✅ Setup app icon from `assets/img/` directory
- Configure for both Android and iOS
- Use Dart package `flutter_launcher_icons`

### Required Assets Location
- `assets/img/app_icon.png` (1024x1024 px, preferably)
- Square format, no rounded corners (Flutter will handle)

### Setup Steps

#### Step 1: Add Dependency to pubspec.yaml
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1
```

#### Step 2: Create flutter_launcher_icons.yaml
```yaml
flutter_launcher_icons:
  image_path: "assets/img/app_icon.png"
  platforms:
    android:
      image_path_android: "assets/img/app_icon.png"
    ios:
      image_path_ios: "assets/img/app_icon.png"
```

#### Step 3: Generate Icons
```bash
dart run flutter_launcher_icons
```

#### Step 4: Update Android Manifest
- Verify `android/app/src/main/AndroidManifest.xml` references icon
- Ensure `mipmap` resources are generated

#### Step 5: Update iOS Info.plist
- Verify `ios/Runner/Info.plist` includes app icon reference

---

## Task 4: Overlay Rendering System Improvements
**Priority**: Critical | **Status**: In Progress (PR #35)

### Issues Identified
- Overlay elements not rendering correctly in preview
- Text/caption positioning misaligned
- Sticker and element overlays not showing
- Rotation transforms not applied properly

### Affected Files
- `lib/pages/editor_page.dart` - Preview canvas rendering
- `lib/widgets/canvas/preview_canvas.dart` - Overlay rendering logic
- `android/app/src/main/kotlin/com/example/flutter_video_editor/OverlayRenderer.kt` - Native overlay rendering
- `ios/Runner/CompositionBuilder.swift` - iOS overlay rendering

### Technical Solutions

#### Flutter Side (preview.dart)
```dart
// Implement proper overlay rendering
void renderOverlays(Canvas canvas, Size size) {
  for (var overlay in overlays) {
    canvas.save();
    
    // Apply position transform
    canvas.translate(
      overlay.positionX * size.width,
      overlay.positionY * size.height,
    );
    
    // Apply rotation with center pivot
    canvas.translate(overlay.width / 2, overlay.height / 2);
    canvas.rotate(overlay.rotation);
    canvas.translate(-overlay.width / 2, -overlay.height / 2);
    
    // Render based on type
    if (overlay.type == OverlayType.text) {
      renderTextOverlay(canvas, overlay);
    } else if (overlay.type == OverlayType.sticker) {
      renderStickerOverlay(canvas, overlay);
    }
    
    canvas.restore();
  }
}
```

#### Android Native (OverlayRenderer.kt)
- Fix text measurement bounds: Use TextPaint.getTextBounds() for precise sizing
- Implement center pivot rotation: Pre-translate by center, rotate, translate back
- Calculate screen coordinates: `(positionX * scaleX, positionY * scaleY)`
- Support SVG/Asset paths: Use AssetManager to load overlay assets

#### iOS Native (CompositionBuilder.swift)
- Calculate CTFrame bounds correctly
- Apply CGAffineTransform for rotation around center
- Use Assets catalog for SVG/image overlays
- Ensure layer compositing order matches preview

### Testing Checklist
- [ ] Text overlay renders at correct position
- [ ] Captions center-aligned and visible
- [ ] Sticker overlays display with correct size
- [ ] Rotation applied without stretching
- [ ] Multi-overlay rendering without conflicts
- [ ] Preview matches exported video

---

## Task 5: Effects & Speed - Real-time Preview & Application
**Priority**: Critical | **Status**: In Progress (PR #18)

### Current Issues
- Effects not applying to video during playback
- Speed changes not showing real-time
- No visual feedback in canvas while editing
- Export doesn't include applied effects

### Affected Components
- `lib/pages/effects_page.dart` - Effect selection UI
- `lib/services/video_processor.dart` - Effect application logic
- `lib/widgets/canvas/preview_canvas.dart` - Real-time rendering
- `lib/pages/speed_sheet.dart` - Speed adjustment UI

### Implementation Steps

#### Step 1: Real-time Effect Application in Preview
```dart
// In preview_canvas.dart
void applyEffectsToFrame(ui.Image frame) {
  final effects = _selectedClip?.effects ?? [];
  
  for (var effect in effects) {
    switch (effect.type) {
      case EffectType.brightness:
        frame = applyBrightnessEffect(frame, effect.intensity);
        break;
      case EffectType.saturation:
        frame = applySaturationEffect(frame, effect.intensity);
        break;
      case EffectType.contrast:
        frame = applyContrastEffect(frame, effect.intensity);
        break;
      case EffectType.blur:
        frame = applyBlurEffect(frame, effect.intensity);
        break;
    }
  }
  
  return frame;
}
```

#### Step 2: Update VideoProcessor Service
```dart
class VideoProcessor {
  Future<void> applyEffectsToExport(
    List<Effect> effects,
    String outputPath,
  ) async {
    // Chain effects in order
    var effectPipeline = effects.map((e) => e.toNative()).toList();
    
    await methodChannel.invokeMethod(
      'applyEffects',
      {
        'effects': effectPipeline,
        'outputPath': outputPath,
      },
    );
  }
}
```

#### Step 3: Add Visual Feedback
- Display current effect values (brightness: 1.2x, blur: 15px, etc.)
- Show live slider updates on canvas
- Implement debounce to prevent excessive frame processing

#### Step 4: Speed Adjustment
```dart
// Speed affects both playback and export
void setVideoSpeed(double speed) {
  _videoPlayer?.setPlaybackSpeed(speed);
  _currentClip?.speed = speed; // Persist for export
  _previewController?.markForUpdate(); // Redraw preview
}
```

### Supported Effects to Implement
- Brightness/Contrast
- Saturation
- Blur
- Grayscale
- Sepia
- Sharpen
- Color Grading (curves)

### Testing Checklist
- [ ] Effect slider changes preview in real-time (< 100ms latency)
- [ ] Speed adjustment updates playback immediately
- [ ] Multiple effects combine correctly
- [ ] Exported video includes all effects
- [ ] Performance remains smooth (60fps on preview)

---

## Task 6: Effects Tool Page in Toolbar
**Priority**: High | **Status**: In Progress (PR #29)

### Objectives
- ✅ Implement dedicated Effects page/sheet
- ✅ Make Effects tool visible in toolbar
- ✅ Apply to all clip selection modes
- Provide intuitive effect sliders and presets

### Toolbar Integration
File: `lib/widgets/toolbar/editor_toolbar.dart`

```dart
// Add Effects tool to toolbar
final toolbarItems = [
  ToolbarItem(
    icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings), // Or effects icon
    label: 'Effects',
    onTap: () => showEffectsSheet(context),
  ),
  // ... other tools
];
```

### Effects Sheet UI Structure
File: `lib/pages/effects_sheet.dart` (create new)

```dart
class EffectsSheet extends StatefulWidget {
  final Clip selectedClip;
  
  @override
  _EffectsSheetState createState() => _EffectsSheetState();
}

class _EffectsSheetState extends State<EffectsSheet> {
  late Map<String, double> effectValues;
  
  @override
  Widget build(BuildContext context) {
    return BottomSheet(
      builder: (context) => Column(
        children: [
          // Sheet header (unified footer from PR #29)
          ToolSheetHeader(title: 'Effects'),
          
          // Effect categories tabs
          SingleChildScrollView(
            child: Column(
              children: [
                // Basic adjustments
                EffectSlider(
                  label: 'Brightness',
                  value: effectValues['brightness'] ?? 0,
                  min: -100,
                  max: 100,
                  onChanged: (val) => applyEffect('brightness', val),
                ),
                EffectSlider(
                  label: 'Contrast',
                  value: effectValues['contrast'] ?? 0,
                  min: -100,
                  max: 100,
                  onChanged: (val) => applyEffect('contrast', val),
                ),
                // ... more sliders
              ],
            ),
          ),
          
          // Footer with presets
          EffectPresetsRow(onPresetSelect: applyPreset),
        ],
      ),
    );
  }
}
```

### Design Requirements (from EditorTokens)
- Use HugeIcons for all effect icons
- White buttons with no gradients
- Monochrome color scheme
- Single bottom sheet footer (PR #29 standard)

### Affected Clip Selection Modes
- Single clip selected
- Multi-clip selection (apply effect to all)
- No clip selected (disable Effects button)

---

## Task 7: Animation & Translation Grid Labels
**Priority**: Medium | **Status**: Pending

### Objectives
- ✅ Add animation names to grid items
- ✅ Add translation names to grid items
- Show labels underneath or overlaid on thumbnails

### Affected Components
- Animation selection grid: `lib/widgets/animation_grid.dart` (or similar)
- Translation selection grid: `lib/widgets/transition_grid.dart` (or similar)

### Implementation Details

#### Animation Grid Labels
```dart
// File: lib/widgets/animation_grid.dart
class AnimationGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (ctx, idx) {
        final animation = animations[idx];
        return Stack(
          children: [
            // Animation preview/thumbnail
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(animation.icon, color: Colors.white),
              ),
            ),
            // Label overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  animation.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

#### Translation Grid Labels
```dart
// File: lib/widgets/transition_grid.dart
class TransitionGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.2,
      ),
      itemBuilder: (ctx, idx) {
        final transition = transitions[idx];
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Transition icon/preview
              Icon(transition.icon, color: Colors.white70, size: 32),
              SizedBox(height: 8),
              // Label
              Text(
                transition.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
```

### Data Structure
```dart
class Animation {
  final String id;
  final String name;        // "Slide Left", "Fade In", etc.
  final IconData icon;
  final AnimationType type;
}

class Transition {
  final String id;
  final String name;        // "Cross Fade", "Slide", etc.
  final IconData icon;
  final Duration duration;
}
```

### Localization Support
- Add to `lib/core/localization/strings.dart` or use Flutter's i18n
- Support multiple languages (English at minimum)

---

## Implementation Priority Order

### Phase 1 (Immediate - This Week)
1. **Task 2**: Button Color Overhaul (quick styling win)
2. **Task 1**: SVG Logo & Watermark (complement to UI refresh)
3. **Task 3**: App Icon Setup (foundational)

### Phase 2 (This Sprint)
4. **Task 4**: Overlay Rendering Improvements (blocking feature quality)
5. **Task 5**: Effects Real-time Preview (core feature fix)
6. **Task 6**: Effects Tool in Toolbar (UI integration)

### Phase 3 (Next Sprint)
7. **Task 7**: Animation/Translation Labels (polish)

---

## Testing & Validation

### Unit Tests to Add
```bash
test/effects_service_test.dart
test/overlay_renderer_test.dart
test/video_processor_test.dart
```

### Widget Tests
```bash
test_driver/editor_page_test.dart
test_driver/effects_sheet_test.dart
test_driver/animation_grid_test.dart
```

### Manual Testing Checklist
- [ ] App launches with SVG logo
- [ ] All buttons are white, no gradients
- [ ] App icon displays correctly (home screen)
- [ ] Overlays render in real-time preview
- [ ] Effects apply instantly and export correctly
- [ ] Speed adjustment works live
- [ ] Effects tool accessible from toolbar
- [ ] Animation/Translation names visible in grid

---

## Dependencies Already Added
✅ `flutter_svg: ^2.3.0` - SVG rendering  
✅ `hugeicons: ^1.2.0` - Icon library  
✅ `google_fonts: ^8.2.1` - Typography  
✅ `provider: ^6.1.2` - State management  
✅ `video_player: ^2.8.2` - Video playback

## Dependencies to Add (if needed)
- `flutter_launcher_icons: ^0.13.1` (Task 3)

---

## Related Pull Requests
- **PR #35**: Use asset logo and fix overlay rendering
- **PR #30**: Fix Android Kotlin compilation errors
- **PR #29**: Fix export asset loading error and refine tool sheet UI
- **PR #25**: Fix FilePicker static access error
- **PR #22**: Add Waveform Styles, Audio Clip Details, and Timeline Audio Lanes
- **PR #18**: Fix video export, real-time effects, snapping, Chroma Key & Extract Audio tools
- **PR #17**: Fix video export, timeline system, tools, effects, and multi-layer rendering
- **PR #12**: Monochrome CapCut-Style Editor Page & Complete Feature Refactoring
- **PR #11**: Migrate to HugeIcons, fix video player preview, and connect real export system

---

## Notes
- Maintain monochrome/strict design aesthetic per existing architecture
- Ensure all UI updates align with EditorTokens design system
- Keep SVG watermark subtle (<5% canvas size, low opacity)
- Test effects performance on lower-end Android devices
- Verify iOS and Android parity for overlay rendering
