import 'package:flutter/material.dart';
import 'captions_edit_sheet.dart';
import 'ai/captions_style.dart';

class CaptionsSheet extends StatefulWidget {
  const CaptionsSheet({super.key});

  @override
  State<CaptionsSheet> createState() => _CaptionsSheetState();
}

class _CaptionsSheetState extends State<CaptionsSheet> {
  bool _isEditing = true;

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return CaptionsEditSheet(
        onOpenStyle: () => setState(() => _isEditing = false),
      );
    } else {
      return CaptionStyleSheet(
        onOpenEdit: () => setState(() => _isEditing = true),
      );
    }
  }
}
