import 'package:flutter/material.dart';

import '../models/app_models.dart';

/// Matches [ChildProfile.supportAreas] values used at signup / My Profile ("Communication", "Learning & Play").
bool childHasCommunicationSupport(ChildProfile? child) {
  if (child == null) {
    return false;
  }
  return child.supportAreas.any(
    (a) => a.toLowerCase().contains('communication'),
  );
}

bool childHasLearningPlaySupport(ChildProfile? child) {
  if (child == null) {
    return false;
  }
  return child.supportAreas.any((a) {
    final l = a.toLowerCase().trim();
    if (l.contains('learning') && l.contains('play')) {
      return true;
    }
    return l == 'learning';
  });
}

void showLockedParentSupportAreaDialog(
  BuildContext context, {
  required String areaLabel,
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Support area locked'),
      content: Text(
        '$areaLabel was not selected for your child. '
        'You can enable this support area in Settings > My Profile > Child section.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
