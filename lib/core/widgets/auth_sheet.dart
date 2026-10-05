import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/core/theme/app_colors.dart';

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AuthSheet(),
    );
  }

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  bool isSignUp = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final user = authController.currentUser;
    final bool isSignedIn = authController.isAuthenticated;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    isSignedIn ? 'User Profile' : (isSignUp ? 'Create Account' : 'Sign In'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (isSignedIn && user != null) ...<Widget>[
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.accent,
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName.substring(0, 1).toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  user.email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await authController.signOut();
                    if (mounted) navigator.pop();
                  },
                ),
              ] else ...<Widget>[
                if (authController.errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Text(
                      authController.errorMessage!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                if (isSignUp) ...<Widget>[
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: authController.isLoading
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            final email = _emailController.text.trim();
                            final password = _passwordController.text.trim();
                            if (isSignUp) {
                              final name = _nameController.text.trim();
                              final ok = await authController.signUp(
                                email: email,
                                password: password,
                                displayName: name,
                              );
                              if (ok && mounted) navigator.pop();
                            } else {
                              final ok = await authController.signIn(
                                email: email,
                                password: password,
                              );
                              if (ok && mounted) navigator.pop();
                            }
                          },
                    child: authController.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(isSignUp ? 'Sign Up' : 'Sign In'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    authController.clearError();
                    setState(() => isSignUp = !isSignUp);
                  },
                  child: Text(
                    isSignUp
                        ? 'Already have an account? Sign In'
                        : "Don't have an account? Sign Up",
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
