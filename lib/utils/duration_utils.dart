int normalizeDurationMinutes(int minutes, {int fallback = 10}) {
  if (minutes > 0) {
    return minutes;
  }
  return fallback;
}

String formatDurationLabel(int totalMinutes) {
  final normalized = normalizeDurationMinutes(totalMinutes);
  final hours = normalized ~/ 60;
  final minutes = normalized % 60;
  if (hours <= 0) {
    return '$minutes min';
  }
  if (minutes == 0) {
    return '$hours hr';
  }
  return '$hours hr $minutes min';
}

int parseDurationLabelToMinutes(String label) {
  final raw = label.trim().toLowerCase();
  if (raw.isEmpty) {
    return 0;
  }

  final hourMatch = RegExp(r'(\d+)\s*(h|hr|hrs|hour|hours)\b').firstMatch(raw);
  final minuteMatch = RegExp(
    r'(\d+)\s*(m|min|mins|minute|minutes)\b',
  ).firstMatch(raw);

  final hours = hourMatch == null ? 0 : int.tryParse(hourMatch.group(1)!) ?? 0;
  final minutes = minuteMatch == null
      ? 0
      : int.tryParse(minuteMatch.group(1)!) ?? 0;

  final parsed = (hours * 60) + minutes;
  if (parsed > 0) {
    return parsed;
  }

  final plainNumber = int.tryParse(raw);
  return plainNumber ?? 0;
}
