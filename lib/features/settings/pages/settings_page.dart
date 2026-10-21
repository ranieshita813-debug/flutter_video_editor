import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';

/// CapCut-style light palette (same values as the auth page).
class _Colors {
  static const Color bg = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF121212);
  static const Color muted = Color(0xFF6B6B70);
  static const Color faint = Color(0xFFA0A0A6);
  static const Color field = Color(0xFFF5F5F7);
  static const Color border = Color(0xFFE4E4E7);
  static const Color primary = Color(0xFF121212);
}

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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _Colors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: _Colors.bg,
      ),
      child: Scaffold(
        backgroundColor: _Colors.bg,
        appBar: AppBar(
          backgroundColor: _Colors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowLeft,
              color: _Colors.text,
              size: 24,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Settings',
            style: TextStyle(
              color: _Colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: <Widget>[
              _buildProfile(auth, user),
              const SizedBox(height: 28),
              _sectionLabel('Export'),
              _group(<Widget>[
                _dropdownRow(
                  icon: PhosphorIconsRegular.filmStrip,
                  title: 'Default resolution',
                  value: _resolution,
                  options: const <String>[
                    '720p (HD)',
                    '1080p (Full HD)',
                    '4K (Ultra HD)',
                  ],
                  onChanged: (v) => setState(() => _resolution = v),
                ),
                _dropdownRow(
                  icon: PhosphorIconsRegular.play,
                  title: 'Default frame rate',
                  value: _frameRate,
                  options: const <String>['24 FPS', '30 FPS', '60 FPS'],
                  onChanged: (v) => setState(() => _frameRate = v),
                ),
                _infoRow(
                  icon: PhosphorIconsRegular.folder,
                  title: 'Export location',
                  subtitle: _exportDirectory,
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel('Performance and storage'),
              _group(<Widget>[
                _switchRow(
                  icon: PhosphorIconsRegular.cpu,
                  title: 'GPU hardware encoding',
                  subtitle: 'Speed up export with Media3 and JNI native pipeline',
                  value: _hardwareAcceleration,
                  onChanged: (v) => setState(() => _hardwareAcceleration = v),
                ),
                _switchRow(
                  icon: PhosphorIconsRegular.floppyDisk,
                  title: 'Auto-save project timeline',
                  subtitle: 'Automatically record project edits locally',
                  value: _autoSave,
                  onChanged: (v) => setState(() => _autoSave = v),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel('About'),
              _group(<Widget>[
                _infoRow(
                  icon: PhosphorIconsRegular.info,
                  title: 'App version',
                  trailing: const Text(
                    '1.0.0 (v1)',
                    style: TextStyle(color: _Colors.muted, fontSize: 13),
                  ),
                ),
                _infoRow(
                  icon: PhosphorIconsRegular.shieldCheck,
                  title: 'Privacy policy',
                  trailing: const PhosphorIcon(
                    PhosphorIconsRegular.caretRight,
                    color: _Colors.faint,
                    size: 16,
                  ),
                  onTap: () {},
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Profile -------------------------------------------------------------

  Widget _buildProfile(AuthController auth, dynamic user) {
    final String initial =
        user != null && user.displayName.isNotEmpty
            ? user.displayName.substring(0, 1).toUpperCase()
            : 'U';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Colors.field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 26,
            backgroundColor: _Colors.primary,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user?.displayName ?? 'Guest user',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _Colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? 'Sign in to back up projects',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _Colors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          auth.isAuthenticated
              ? OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _Colors.bg,
                    side: const BorderSide(color: _Colors.border),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: auth.signOut,
                  child: const Text(
                    'Sign out',
                    style: TextStyle(
                      color: _Colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Colors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: () => Navigator.of(context).pushNamed('/auth'),
                  child: const Text(
                    'Sign in',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
        ],
      ),
    );
  }

  // ---- Building blocks -----------------------------------------------------

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: _Colors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _group(List<Widget> rows) {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(const Divider(
          height: 1,
          indent: 56,
          color: _Colors.border,
        ));
      }
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: _Colors.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _leading(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _Colors.field,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: PhosphorIcon(icon, color: _Colors.text, size: 18),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: _leading(icon),
      title: Text(
        title,
        style: const TextStyle(
          color: _Colors.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: _Colors.muted, fontSize: 12),
            ),
      trailing: trailing,
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      activeThumbColor: Colors.white,
      activeTrackColor: _Colors.primary,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: const Color(0xFFD4D4D8),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      secondary: _leading(icon),
      title: Text(
        title,
        style: const TextStyle(
          color: _Colors.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: _Colors.muted, fontSize: 12),
      ),
    );
  }

  Widget _dropdownRow({
    required IconData icon,
    required String title,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: _leading(icon),
      title: Text(
        title,
        style: const TextStyle(
          color: _Colors.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: DropdownButton<String>(
        value: value,
        dropdownColor: _Colors.bg,
        borderRadius: BorderRadius.circular(14),
        underline: const SizedBox.shrink(),
        icon: const PhosphorIcon(
          PhosphorIconsRegular.caretDown,
          color: _Colors.muted,
          size: 14,
        ),
        items: options
            .map(
              (String v) => DropdownMenuItem<String>(
                value: v,
                child: Text(
                  v,
                  style: const TextStyle(color: _Colors.text, fontSize: 13),
                ),
              ),
            )
            .toList(),
        onChanged: (String? v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}