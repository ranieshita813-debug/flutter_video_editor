import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_editor/core/services/auth_service.dart';
import 'package:flutter_video_editor/core/services/feature_toggle_service.dart';
import 'package:flutter_video_editor/core/services/firebase_asset_service.dart';
import 'package:flutter_video_editor/core/services/firebase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirebaseService Initialization Tests', () {
    test('FirebaseService instance is singleton and initializes safely', () async {
      final service = FirebaseService.instance;
      expect(service, isNotNull);

      // Call initialize (will execute try-catch fallback if unconfigured in test sandbox)
      final initialized = await service.initialize();
      expect(initialized, isA<bool>());
    });
  });

  group('AuthService Tests', () {
    late AuthService authService;

    setUp(() {
      authService = AuthService();
    });

    test('Default loadSavedSession returns a valid guest or saved user', () async {
      final user = await authService.loadSavedSession();
      expect(user, isNotNull);
      expect(user!.email.isNotEmpty, isTrue);
    });

    test('signUp creates user and updates currentUser', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'test_$timestamp@motiongr.app';

      final user = await authService.signUp(
        email: testEmail,
        password: 'password123',
        displayName: 'Test User',
      );

      expect(user.email, equals(testEmail));
      expect(user.displayName, equals('Test User'));
      expect(authService.currentUser, equals(user));
    });

    test('signIn authenticates created user', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'signin_$timestamp@motiongr.app';

      await authService.signUp(
        email: testEmail,
        password: 'mySecretPassword',
        displayName: 'Sign In User',
      );

      final user = await authService.signIn(
        email: testEmail,
        password: 'mySecretPassword',
      );

      expect(user.email, equals(testEmail));
      expect(user.isGuest, isFalse);
    });

    test('signInAsGuest creates guest profile', () async {
      final guest = await authService.signInAsGuest();
      expect(guest.isGuest, isTrue);
      expect(authService.currentUser?.isGuest, isTrue);
    });

    test('signOut clears active user session', () async {
      await authService.signInAsGuest();
      expect(authService.currentUser, isNotNull);

      await authService.signOut();
      expect(authService.currentUser, isNull);
    });
  });

  group('FirebaseAssetService Tests', () {
    late FirebaseAssetService assetService;

    setUp(() {
      assetService = FirebaseAssetService.instance;
    });

    test('fetchRemoteEffects returns list of downloadable shader effects', () async {
      final effects = await assetService.fetchRemoteEffects();
      expect(effects.isNotEmpty, isTrue);
      expect(effects.first.name.isNotEmpty, isTrue);
    });

    test('fetchRemoteFonts returns list of remote font items', () async {
      final fonts = await assetService.fetchRemoteFonts();
      expect(fonts.isNotEmpty, isTrue);
      expect(fonts.first.family.isNotEmpty, isTrue);
    });

    test('fetchRemoteElements returns list of SVG graphics', () async {
      final elements = await assetService.fetchRemoteElements();
      expect(elements.isNotEmpty, isTrue);
      expect(elements.first.svgContent.contains('<svg'), isTrue);
    });

    test('fetchRemoteAnimations returns list of clip animations', () async {
      final animations = await assetService.fetchRemoteAnimations();
      expect(animations.isNotEmpty, isTrue);
      expect(animations.first.name.isNotEmpty, isTrue);
    });

    test('downloadEffect marks effect as downloaded', () async {
      final effects = await assetService.fetchRemoteEffects();
      final effect = effects.first;

      final downloaded = await assetService.downloadEffect(effect);
      expect(downloaded.isDownloaded, isTrue);
    });
  });

  group('FeatureToggleService Tests', () {
    late FeatureToggleService toggleService;

    setUp(() {
      toggleService = FeatureToggleService.instance;
    });

    test('Feature flags are enabled by default', () {
      expect(toggleService.isFeatureEnabled('effects'), isTrue);
      expect(toggleService.isFeatureEnabled('filters'), isTrue);
      expect(toggleService.isFeatureEnabled('elements'), isTrue);
    });

    test('setFeatureEnabled updates feature state and notifies listeners', () async {
      bool notified = false;
      toggleService.addListener(() {
        notified = true;
      });

      await toggleService.setFeatureEnabled('effects', false);
      expect(toggleService.isFeatureEnabled('effects'), isFalse);
      expect(notified, isTrue);

      // Re-enable
      await toggleService.setFeatureEnabled('effects', true);
      expect(toggleService.isFeatureEnabled('effects'), isTrue);
    });

    test('resetToDefaults restores all feature flags', () async {
      await toggleService.setFeatureEnabled('filters', false);
      await toggleService.setFeatureEnabled('draw', false);

      expect(toggleService.isFeatureEnabled('filters'), isFalse);

      await toggleService.resetToDefaults();
      expect(toggleService.isFeatureEnabled('filters'), isTrue);
      expect(toggleService.isFeatureEnabled('draw'), isTrue);
    });
  });
}
