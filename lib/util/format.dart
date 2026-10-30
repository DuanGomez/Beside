import 'package:intl/intl.dart';

final _day = DateFormat("EEEE d 'de' MMMM", 'es');

/// "5:48 a. m."
String hour(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'a. m.' : 'p. m.'}';
}

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  final s = _day.format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// "hace 5 s", "hace 3 min", "hace 2 h"
String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 5) return 'ahora';
  if (d.inSeconds < 60) return 'hace ${d.inSeconds} s';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} d';
}

/// "52 min", "2 h 10 min"
String duration(Duration d) {
  if (d.inMinutes < 1) return 'menos de 1 min';
  if (d.inHours < 1) return '${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
}

String km(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final v = meters / 1000;
  return '${v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', ',')} km';
}

String mmss(int ms) {
  final s = (ms / 1000).floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
