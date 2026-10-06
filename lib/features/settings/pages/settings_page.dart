import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _resolution = '1080p (Full HD)';
  String _frameRate = '30 FPS';
  final String _exportDirectory = '/storage/emulated/0/MotionGr';
  bool _hardwareAcceleration = true;
  bool _autoSave = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.currentUser;

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
        title: const Text(
          'App Settings',
          style: TextStyle(
            color: EditorTokens.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: EditorTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EditorTokens.border),
              ),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: EditorTokens.accent,
                    child: Text(
                      user != null && user.displayName.isNotEmpty
                          ? user.displayName.substring(0, 1).toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user?.displayName ?? 'Guest User',
                          style: const TextStyle(
                            color: EditorTokens.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? 'Sign in to back up projects',
                          style: const TextStyle(
                            color: EditorTokens.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: EditorTokens.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      if (auth.isAuthenticated) {
                        auth.signOut();
                      } else {
                        Navigator.of(context).pushNamed('/auth');
                      }
                    },
                    child: Text(
                      auth.isAuthenticated ? 'Sign Out' : 'Sign In',
                      style: const TextStyle(
                        color: EditorTokens.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'EXPORT PREFERENCES',
                style: TextStyle(
                  color: EditorTokens.faint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: EditorTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EditorTokens.border),
              ),
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedVideo01,
                      color: EditorTokens.text,
                      size: 20,
                    ),
                    title: const Text('Default Resolution',
                        style: TextStyle(color: EditorTokens.text, fontSize: 14)),
                    subtitle: Text(_resolution,
                        style: const TextStyle(color: EditorTokens.muted, fontSize: 12)),
                    trailing: DropdownButton<String>(
                      value: _resolution,
                      dropdownColor: EditorTokens.elevated,
                      underline: const SizedBox.shrink(),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        color: EditorTokens.muted,
                        size: 16,
                      ),
                      items: const <String>[
                        '720p (HD)',
                        '1080p (Full HD)',
                        '4K (Ultra HD)'
                      ].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: const TextStyle(
                                  color: EditorTokens.text, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _resolution = val);
                      },
                    ),
                  ),
                  const Divider(height: 1, color: EditorTokens.border),
                  ListTile(
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedPlay,
                      color: EditorTokens.text,
                      size: 20,
                    ),
                    title: const Text('Default Frame Rate',
                        style: TextStyle(color: EditorTokens.text, fontSize: 14)),
                    subtitle: Text(_frameRate,
                        style: const TextStyle(color: EditorTokens.muted, fontSize: 12)),
                    trailing: DropdownButton<String>(
                      value: _frameRate,
                      dropdownColor: EditorTokens.elevated,
                      underline: const SizedBox.shrink(),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        color: EditorTokens.muted,
                        size: 16,
                      ),
                      items: const <String>['24 FPS', '30 FPS', '60 FPS']
                          .map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: const TextStyle(
                                  color: EditorTokens.text, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _frameRate = val);
                      },
                    ),
                  ),
                  const Divider(height: 1, color: EditorTokens.border),
                  ListTile(
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                      color: EditorTokens.text,
                      size: 20,
                    ),
                    title: const Text('Export Storage Location',
                        style: TextStyle(color: EditorTokens.text, fontSize: 14)),
                    subtitle: Text(_exportDirectory,
                        style: const TextStyle(color: EditorTokens.muted, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'PERFORMANCE & STORAGE',
                style: TextStyle(
                  color: EditorTokens.faint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: EditorTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EditorTokens.border),
              ),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    value: _hardwareAcceleration,
                    activeThumbColor: Colors.black,
                    activeTrackColor: EditorTokens.accent,
                    secondary: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCpu,
                      color: EditorTokens.text,
                      size: 20,
                    ),
                    title: const Text('GPU Hardware Encoding',
                        style: TextStyle(color: EditorTokens.text, fontSize: 14)),
                    subtitle: const Text('Speed up export with Media3 & JNI native pipeline',
                        style: TextStyle(color: EditorTokens.muted, fontSize: 12)),
                    onChanged: (val) => setState(() => _hardwareAcceleration = val),
                  ),
                  const Divider(height: 1, color: EditorTokens.border),
                  SwitchListTile(
                    value: _autoSave,
                    activeThumbColor: Colors.black,
                    activeTrackColor: EditorTokens.accent,
                    secondary: const HugeIcon(
                      icon: HugeIcons.strokeRoundedPencilEdit02,
                      color: EditorTokens.text,
                      size: 20,
                    ),
                    title: const Text('Auto Save Project Timeline',
                        style: TextStyle(color: EditorTokens.text, fontSize: 14)),
                    subtitle: const Text('Automatically record project edits locally',
                        style: TextStyle(color: EditorTokens.muted, fontSize: 12)),
                    onChanged: (val) => setState(() => _autoSave = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'ABOUT',
                style: TextStyle(
                  color: EditorTokens.faint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: EditorTokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EditorTokens.border),
              ),
              child: Column(
                children: <Widget>[
                  const ListTile(
                    leading: HugeIcon(
                      icon: HugeIcons.strokeRoundedInformationCircle,
                      color: EditorTokens.text,
                      size: 20,
                    ),
                    title: Text('App Version',
                        style: TextStyle(color: EditorTokens.text, fontSize: 14)),
                    trailing: Text('1.0.0 (v1)',
                        style: TextStyle(color: EditorTokens.muted, fontSize: 13)),
                  ),
                  const Divider(height: 1, color: EditorTokens.border),
                  ListTile(
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedShieldCheck,
                      color: EditorTokens.text,
                      size: 20,
                    ),
                    title: const Text('Privacy Policy',
                        style: TextStyle(color: EditorTokens.text, fontSize: 14)),
                    trailing: const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      color: EditorTokens.muted,
                      size: 16,
                    ),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
