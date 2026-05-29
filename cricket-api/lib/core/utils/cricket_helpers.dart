import 'package:intl/intl.dart';

/// Format cricket overs correctly: 19.6 -> 20.0, 5.3 -> 5.3
String formatCricketOvers(dynamic overs) {
  if (overs == null) return '';
  final text = overs.toString();
  if (text.isEmpty || text == '0' || text == '0.0') return text;
  final parts = text.split('.');
  if (parts.length != 2) return text;

  final over = int.tryParse(parts[0]) ?? 0;
  final balls = int.tryParse(parts[1]) ?? 0;

  if (balls >= 6) {
    return '${over + 1}.0';
  }
  return '$over.$balls';
}

/// Format overs text for display: "(20.0)" or "(18.5 ov)"
String formatOversText(dynamic overs, {bool withOv = true}) {
  final formatted = formatCricketOvers(overs);
  if (formatted.isEmpty) return '';
  return withOv ? '($formatted ov)' : '($formatted)';
}

/// Format score text with proper overs: "147/8 (20.0 ov)"
String formatScoreWithOvers(int runs, int wickets, dynamic overs) {
  final ov = formatCricketOvers(overs);
  return '$runs/$wickets ($ov ov)';
}

/// Format match time to local compact format: "7:30 PM"
String formatMatchTime(DateTime? dateTime) {
  if (dateTime == null) return '';
  final local = dateTime.toLocal();
  return DateFormat('h:mm a').format(local);
}

/// Format date for grouping: "Today", "Tomorrow", "Sunday, 25 May"
String formatDateGroup(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff > 1 && diff <= 6) return DateFormat('EEEE').format(date);
  return DateFormat('EEE, d MMM').format(date);
}

/// Parse a date string like "March 19, 2025" to DateTime
DateTime? parseScheduleDate(String dateStr) {
  if (dateStr.isEmpty) return null;
  try {
    return DateFormat('MMMM d, yyyy').parse(dateStr);
  } catch (_) {
    try {
      return DateFormat('MMM d, yyyy').parse(dateStr);
    } catch (_) {
      return null;
    }
  }
}

/// Format time ago from timestamp
String formatTimeAgo(dynamic timestamp) {
  if (timestamp == null) return '';
  DateTime? dt;
  if (timestamp is int) {
    dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  } else if (timestamp is String) {
    final ms = int.tryParse(timestamp);
    if (ms != null) {
      dt = DateTime.fromMillisecondsSinceEpoch(ms);
    } else {
      dt = DateTime.tryParse(timestamp);
    }
  }
  if (dt == null) return '';

  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(dt);
}
