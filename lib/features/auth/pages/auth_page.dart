import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/core/widgets/loading_wave.dart';

/// CapCut-style light palette (scoped to the auth page).
class _AuthColors {
  static const Color bg = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF121212);
  static const Color muted = Color(0xFF6B6B70);
  static const Color faint = Color(0xFFA0A0A6);
  static const Color field = Color(0xFFF3F3F5);
  static const Color border = Color(0xFFE4E4E7);
  static const Color primary = Color(0xFF121212);
  static const Color link = Color(0xFF00B8A9);
  static const Color error = Color(0xFFE5484D);
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isSignUp = false;
  bool _showEmailForm = false;
  bool _obscure = true;
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    final auth = context.read<AuthController>();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    bool success = false;
    if (_isSignUp) {
      success = await auth.signUp(
        email: email,
        password: password,
        displayName: name.isEmpty ? email.split('@').first : name,
      );
    } else {
      success = await auth.signIn(email: email, password: password);
    }

    if (mounted && success) {
      Navigator.of(context).pop();
    }
  }

  void _socialSignIn(String provider) async {
    final auth = context.read<AuthController>();
    final success = await auth.signUp(
      email: '${provider.toLowerCase()}_user@motiongr.app',
      password: 'social_password_123',
      displayName: '$provider User',
    );
    if (mounted && success) {
      Navigator.of(context).pop();
    }
  }

  InputDecoration _fieldDecoration(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _AuthColors.faint, fontSize: 15),
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: PhosphorIcon(icon, color: _AuthColors.muted, size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48),
      suffixIcon: suffix,
      filled: true,
      fillColor: _AuthColors.field,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AuthColors.text, width: 1.4),
      ),
    );
  }

  Widget _socialButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: _AuthColors.bg,
          side: const BorderSide(color: _AuthColors.border, width: 1.2),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        onPressed: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: PhosphorIcon(icon, color: _AuthColors.text, size: 22),
            ),
            Text(
              label,
              style: const TextStyle(
                color: _AuthColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _AuthColors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: _AuthColors.bg,
      ),
      child: Scaffold(
        backgroundColor: _AuthColors.bg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              // Top bar: close button only, like CapCut.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const PhosphorIcon(
                      PhosphorIconsRegular.x,
                      color: _AuthColors.text,
                      size: 24,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 16),
                      Center(
                        child: SvgPicture.asset(
                          'assets/logo_white.svg',
                          height: 44,
                          // Logo asset is white; tint it for the light theme.
                          colorFilter: const ColorFilter.mode(
                            _AuthColors.text,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _isSignUp ? 'Create your account' : 'Welcome back',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _AuthColors.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSignUp
                            ? 'Sign up to sync projects and export videos'
                            : 'Sign in to access your motionGr account',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _AuthColors.muted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Social buttons first (CapCut pattern).
                      _socialButton(
                        icon: PhosphorIconsRegular.googleLogo,
                        label: 'Continue with Google',
                        onTap: () => _socialSignIn('Google'),
                      ),
                      const SizedBox(height: 12),
                      _socialButton(
                        icon: PhosphorIconsRegular.facebookLogo,
                        label: 'Continue with Facebook',
                        onTap: () => _socialSignIn('Facebook'),
                      ),
                      const SizedBox(height: 12),
                      _socialButton(
                        icon: PhosphorIconsRegular.envelopeSimple,
                        label: _showEmailForm
                            ? 'Hide email options'
                            : 'Continue with Email',
                        onTap: () {
                          auth.clearError();
                          setState(() => _showEmailForm = !_showEmailForm);
                        },
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _showEmailForm
                            ? _buildEmailForm(auth)
                            : const SizedBox(width: double.infinity),
                      ),

                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            _isSignUp
                                ? 'Already have an account? '
                                : 'New to motionGr? ',
                            style: const TextStyle(
                              color: _AuthColors.muted,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              auth.clearError();
                              setState(() => _isSignUp = !_isSignUp);
                            },
                            child: Text(
                              _isSignUp ? 'Sign in' : 'Sign up',
                              style: const TextStyle(
                                color: _AuthColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Terms footer pinned to the bottom.
              const Padding(
                padding: EdgeInsets.fromLTRB(32, 8, 32, 16),
                child: Text(
                  'By continuing, you agree to our Terms of Service and acknowledge our Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _AuthColors.faint,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm(AuthController auth) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_isSignUp) ...<Widget>[
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              cursorColor: _AuthColors.text,
              style: const TextStyle(color: _AuthColors.text, fontSize: 15),
              decoration:
                  _fieldDecoration('Full name', PhosphorIconsRegular.user),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            cursorColor: _AuthColors.text,
            style: const TextStyle(color: _AuthColors.text, fontSize: 15),
            decoration:
                _fieldDecoration('Email address', PhosphorIconsRegular.envelope),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            cursorColor: _AuthColors.text,
            style: const TextStyle(color: _AuthColors.text, fontSize: 15),
            onSubmitted: (_) => auth.isLoading ? null : _submit(),
            decoration: _fieldDecoration(
              'Password',
              PhosphorIconsRegular.lock,
              suffix: IconButton(
                icon: PhosphorIcon(
                  _obscure
                      ? PhosphorIconsRegular.eyeSlash
                      : PhosphorIconsRegular.eye,
                  color: _AuthColors.muted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (auth.errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              auth.errorMessage!,
              style: const TextStyle(color: _AuthColors.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _AuthColors.primary,
                disabledBackgroundColor: _AuthColors.primary.withOpacity(0.85),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
              ),
              onPressed: auth.isLoading ? null : _submit,
              child: auth.isLoading
                  ? const TextShimmerWave(
                      'Authenticating…',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      baseColor: Colors.white54,
                      waveColor: Colors.white,
                    )
                  : Text(
                      _isSignUp ? 'Create account' : 'Sign in',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}