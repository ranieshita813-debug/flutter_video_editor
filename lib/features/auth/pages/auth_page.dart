import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isSignUp = false;
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: EditorTokens.bg,
      appBar: AppBar(
        backgroundColor: EditorTokens.bg,
        elevation: 0,
        leading: IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            color: EditorTokens.text,
            size: 22,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isSignUp ? 'Create Account' : 'Sign In',
          style: const TextStyle(
            color: EditorTokens.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'motionGr',
                  style: GoogleFonts.unbounded(
                    color: EditorTokens.accent,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _isSignUp
                      ? 'Sign up to sync projects and export videos'
                      : 'Sign in to access your motionGr account',
                  style: const TextStyle(
                    color: EditorTokens.muted,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              if (_isSignUp) ...<Widget>[
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: EditorTokens.text, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: const TextStyle(color: EditorTokens.muted),
                    prefixIcon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedUser,
                      color: EditorTokens.muted,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: EditorTokens.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: EditorTokens.text, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: const TextStyle(color: EditorTokens.muted),
                  prefixIcon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedMail01,
                    color: EditorTokens.muted,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: EditorTokens.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                style: const TextStyle(color: EditorTokens.text, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: EditorTokens.muted),
                  prefixIcon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedLockPassword,
                    color: EditorTokens.muted,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: EditorTokens.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (auth.errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  auth.errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EditorTokens.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: auth.isLoading ? null : _submit,
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          _isSignUp ? 'Create Account' : 'Sign In',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 28),
              const Row(
                children: <Widget>[
                  Expanded(child: Divider(color: EditorTokens.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR CONTINUE WITH',
                      style: TextStyle(
                        color: EditorTokens.faint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: EditorTokens.border)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: EditorTokens.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _socialSignIn('Google'),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedGoogle,
                        color: EditorTokens.text,
                        size: 20,
                      ),
                      label: const Text(
                        'Google',
                        style: TextStyle(color: EditorTokens.text, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: EditorTokens.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _socialSignIn('Facebook'),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedFacebook01,
                        color: EditorTokens.text,
                        size: 20,
                      ),
                      label: const Text(
                        'Facebook',
                        style: TextStyle(color: EditorTokens.text, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    _isSignUp
                        ? 'Already have an account? '
                        : 'Don\'t have an account? ',
                    style: const TextStyle(
                      color: EditorTokens.muted,
                      fontSize: 13,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      auth.clearError();
                      setState(() => _isSignUp = !_isSignUp);
                    },
                    child: Text(
                      _isSignUp ? 'Sign In' : 'Sign Up',
                      style: const TextStyle(
                        color: EditorTokens.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
