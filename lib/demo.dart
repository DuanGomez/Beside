import 'dart:async';
import 'dart:math';

import 'package:latlong2/latlong.dart' show LatLng;

import 'services/app_state.dart';

/// Datos de ejemplo para la vista previa (Medellín). Nada se guarda.
class Demo {
  static final _r = Random(7);
  static Timer? _timer;

  static const _gym = LatLng(6.20830, -75.56790);
  static const _herHome = LatLng(6.21720, -75.57620);
  static const _myHome = LatLng(6.24420, -75.58120);
  static const _herWork = LatLng(6.20130, -75.57280);
  static const _momWork = LatLng(6.25180, -75.56360);

  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  static void seed() {
    final s = AppState.instance..demo = true;
    final now = DateTime.now();

    s.members
      ..clear()
      ..addAll({
        'me': Member(id: 'me', name: 'Duan', color: '#7FC8F2'),
        'amor': Member(id: 'amor', name: 'Mi amor', color: '#F2789A'),
        'mama': Member(id: 'mama', name: 'Mamá', color: '#A99BF5'),
      });
    s.circles
      ..clear()
      ..add(Circle(id: 'c1', name: 'Familia', code: 'BSD-4K7Q'));

    Map<String, dynamic> place(String id, String name, String icon, LatLng p, int r, {bool exit = false}) =>
        {'id': id, 'circle_id': 'c1', 'name': name, 'icon': icon, 'lat': p.latitude, 'lng': p.longitude, 'radius_m': r, 'notify_enter': true, 'notify_exit': exit};
    s.places
      ..clear()
      ..addAll([
        Place(place('p1', 'Gym', 'gym', _gym, 120, exit: true)),
        Place(place('p2', 'Casa de ella', 'heart', _herHome, 80, exit: true)),
        Place(place('p3', 'Mi casa', 'home', _myHome, 70)),
        Place(place('p4', 'Trabajo de ella', 'work', _herWork, 100, exit: true)),
        Place(place('p5', 'Trabajo de mamá', 'work', _momWork, 100)),
      ]);

    s.lives
      ..clear()
      ..addAll({
        'amor': Live({
          'user_id': 'amor', 'lat': _gym.latitude + 0.0002, 'lng': _gym.longitude - 0.0001, 'accuracy': 6.0, 'speed': 0.0,
          'battery': 78, 'charging': false, 'place_id': 'p1', 'place_since': _iso(now.subtract(const Duration(minutes: 52))),
          'updated_at': _iso(now),
          'track_name': 'Ojitos Lindos', 'track_artist': 'Bad Bunny, Bomba Estéreo', 'track_progress_ms': 106000,
          'track_duration_ms': 258000, 'track_playing': true, 'track_at': _iso(now),
        }),
        'mama': Live({
          'user_id': 'mama', 'lat': _momWork.latitude, 'lng': _momWork.longitude, 'accuracy': 12.0, 'speed': 0.0,
          'battery': 54, 'charging': true, 'place_id': 'p5', 'place_since': _iso(now.subtract(const Duration(hours: 3))),
          'updated_at': _iso(now.subtract(const Duration(minutes: 1))),
        }),
        'me': Live({
          'user_id': 'me', 'lat': _myHome.latitude, 'lng': _myHome.longitude, 'accuracy': 8.0, 'speed': 0.0,
          'battery': 91, 'charging': false, 'place_id': 'p3', 'place_since': _iso(now.subtract(const Duration(hours: 1))),
          'updated_at': _iso(now),
        }),
      });

    s.events
      ..clear()
      ..addAll([
        PlaceEvent({'id': 4, 'user_id': 'amor', 'place_id': 'p1', 'place_name': 'Gym', 'kind': 'enter', 'at': _iso(now.subtract(const Duration(minutes: 52)))}),
        PlaceEvent({'id': 3, 'user_id': 'amor', 'place_id': 'p2', 'place_name': 'Casa de ella', 'kind': 'exit', 'at': _iso(now.subtract(const Duration(minutes: 71)))}),
        PlaceEvent({'id': 2, 'user_id': 'mama', 'place_id': 'p5', 'place_name': 'Trabajo de mamá', 'kind': 'enter', 'at': _iso(now.subtract(const Duration(hours: 3)))}),
      ]);
    s.selectedId = 'amor';

    // "En vivo": cada pocos segundos llega una lectura nueva con un leve temblor del GPS
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      final l = s.lives['amor']!.m;
      l['lat'] = _gym.latitude + 0.0002 + (_r.nextDouble() - 0.5) * 0.00004;
      l['lng'] = _gym.longitude - 0.0001 + (_r.nextDouble() - 0.5) * 0.00004;
      l['updated_at'] = _iso(DateTime.now());
      s.lives['me']!.m['updated_at'] = _iso(DateTime.now());
      s.changed();
    });
  }

  /// Recorrido de ejemplo de un día: casa de ella → trabajo → gym.
  static List<Map<String, dynamic>> history(String userId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day, 5, 30);
    final route = <LatLng>[_herHome, const LatLng(6.2140, -75.5745), const LatLng(6.2100, -75.5712), _gym];
    final points = <Map<String, dynamic>>[];
    var t = start;
    for (var i = 0; i < route.length - 1; i++) {
      for (var k = 0; k < 12; k++) {
        final a = route[i], b = route[i + 1];
        final f = k / 12;
        points.add({
          'lat': a.latitude + (b.latitude - a.latitude) * f + (_r.nextDouble() - 0.5) * 0.0002,
          'lng': a.longitude + (b.longitude - a.longitude) * f + (_r.nextDouble() - 0.5) * 0.0002,
          'speed': 6.5,
          'accuracy': 8.0,
          'recorded_at': _iso(t),
        });
        t = t.add(const Duration(seconds: 50));
      }
    }
    points.add({'lat': _gym.latitude, 'lng': _gym.longitude, 'speed': 0.0, 'accuracy': 6.0, 'recorded_at': _iso(t)});
    return userId == 'amor' ? points : points.take(6).toList();
  }
}
