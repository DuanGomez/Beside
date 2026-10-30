import 'dart:async';
import 'dart:convert';
import 'package:beside/util/platform.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'spotify_api.dart';

/// Comparte la ubicación, la batería y la canción de Spotify.
///
/// En Android corre dentro del servicio en primer plano (sigue vivo con la app
/// cerrada y arranca solo al prender el celular). En iPhone corre en la app y
/// continúa en segundo plano mientras iOS entregue ubicaciones.
///
/// No usa la sesión de Supabase: publica con la llave del dispositivo, así nunca
/// se detiene porque la sesión venció.
class Tracker {
  static const _goodAccuracy = 50.0; // metros
  static const _worstAccuracy = 150.0;

  StreamSubscription<Position>? _sub;
  Timer? _beat;
  Timer? _spotifyTimer;
  String? _deviceKey;
  bool _moving = true;
  bool _running = false;

  Position? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFixAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastGoodAt = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _lastPoint;
  DateTime _lastPointAt = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _anchor;
  DateTime _anchorAt = DateTime.now();
  final List<Map<String, dynamic>> _pending = [];
  bool _sending = false;

  final _battery = Battery();
  String? _lastTrackKey;
  DateTime _lastTrackSent = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (_running) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _deviceKey = prefs.getString('device_key');
    if (_deviceKey == null || !Config.isConfigured) return;
    _running = true;
    _listen(moving: true);
    _beat = Timer.periodic(const Duration(seconds: 60), (_) => _heartbeat());
    _spotifyTimer = Timer.periodic(const Duration(seconds: 20), (_) => _pollSpotify());
    unawaited(_pollSpotify());
    // Primera posición inmediata, sin esperar al primer movimiento
    unawaited(_freshFix());
  }

  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _beat?.cancel();
    _spotifyTimer?.cancel();
    _sub = null;
  }

  // ------------------------------------------------------------------
  // Ubicación
  // ------------------------------------------------------------------

  LocationSettings _settings(bool moving) {
    if (isAndroid) {
      return AndroidSettings(
        accuracy: moving ? LocationAccuracy.best : LocationAccuracy.medium,
        distanceFilter: 0,
        intervalDuration: Duration(seconds: moving ? 4 : 30),
      );
    }
    return AppleSettings(
      accuracy: moving ? LocationAccuracy.best : LocationAccuracy.medium,
      distanceFilter: moving ? 5 : 30,
      activityType: ActivityType.other,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: false,
    );
  }

  void _listen({required bool moving}) {
    _moving = moving;
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings(moving)).listen(
      _onPosition,
      onError: (_) {
        // El GPS se apagó o falló: reintentar sin detener el servicio
        Future.delayed(const Duration(seconds: 15), () {
          if (_running) _listen(moving: _moving);
        });
      },
    );
  }

  Future<void> _freshFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: const Duration(seconds: 25)),
      );
      _onPosition(p, force: true);
    } catch (_) {
      // Sin señal por ahora; el siguiente latido lo vuelve a intentar
    }
  }

  void _onPosition(Position p, {bool force = false}) {
    final now = DateTime.now();
    _lastFixAt = now;
    if (p.accuracy > _worstAccuracy) return;

    final good = p.accuracy <= _goodAccuracy;
    if (good) _lastGoodAt = now;
    // Lecturas imprecisas solo cuentan si hace rato no hay una buena
    if (!good && now.difference(_lastGoodAt) < const Duration(minutes: 2) && !force) return;

    if (_lastSent != null) {
      final d = _distance(_lastSent!, p);
      final dt = p.timestamp.difference(_lastSent!.timestamp).inMilliseconds / 1000;
      // Saltos imposibles (más de 250 km/h) son errores del GPS
      if (dt > 0 && d / dt > 70 && d > 200) return;
    }

    // Movimiento: un ancla que se reubica cuando se aleja más de 40 m
    if (_anchor == null || _distance(_anchor!, p) > 40 || p.speed > 2) {
      _anchor = p;
      _anchorAt = now;
      if (!_moving) _listen(moving: true);
    } else if (_moving && now.difference(_anchorAt) > const Duration(minutes: 3)) {
      _listen(moving: false); // quieta: ahorra batería sin perder precisión
    }

    final sinceSent = now.difference(_lastSentAt);
    final moved = _lastSent == null ? double.infinity : _distance(_lastSent!, p);
    final shouldSend = force || moved >= 8 || sinceSent >= Duration(seconds: _moving ? 15 : 60);
    if (!shouldSend) return;

    final savePoint = p.accuracy <= 60 &&
        (_lastPoint == null || _distance(_lastPoint!, p) >= 25 || now.difference(_lastPointAt) >= const Duration(minutes: 10));
    if (savePoint) {
      _lastPoint = p;
      _lastPointAt = now;
    }
    _lastSent = p;
    _lastSentAt = now;
    unawaited(_send(p, savePoint));
  }

  Future<void> _send(Position p, bool savePoint) async {
    int? level;
    bool? charging;
    try {
      level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      charging = state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {}

    final ok = await _rpc('push_location', {
      'p_lat': p.latitude,
      'p_lng': p.longitude,
      'p_accuracy': p.accuracy,
      'p_speed': p.speed < 0 ? null : p.speed,
      'p_heading': p.heading < 0 ? null : p.heading,
      'p_battery': level,
      'p_charging': charging,
      'p_save_point': savePoint,
      'p_recorded_at': p.timestamp.toUtc().toIso8601String(),
    });

    if (!ok && savePoint) {
      // Sin internet: guardar el punto para enviarlo después (máximo 600)
      _pending.add({
        'lat': p.latitude,
        'lng': p.longitude,
        'accuracy': p.accuracy,
        'speed': p.speed < 0 ? null : p.speed,
        'at': p.timestamp.toUtc().toIso8601String(),
      });
      if (_pending.length > 600) _pending.removeAt(0);
    } else if (ok && _pending.isNotEmpty && !_sending) {
      _sending = true;
      final batch = List<Map<String, dynamic>>.from(_pending);
      if (await _rpc('push_points', {'points': batch})) _pending.removeRange(0, batch.length.clamp(0, _pending.length));
      _sending = false;
    }
  }

  Future<void> _heartbeat() async {
    if (!_running) return;
    final now = DateTime.now();
    if (now.difference(_lastFixAt) > const Duration(minutes: 3)) {
      // El GPS no ha entregado nada: pedir una lectura directa y revivir el flujo
      await _freshFix();
      if (DateTime.now().difference(_lastFixAt) > const Duration(minutes: 3)) _listen(moving: _moving);
      return;
    }
    if (now.difference(_lastSentAt) >= const Duration(seconds: 55)) {
      if (_lastSent != null) {
        _lastSentAt = now;
        unawaited(_send(_lastSent!, false));
      }
    }
  }

  // ------------------------------------------------------------------
  // Spotify
  // ------------------------------------------------------------------

  Future<void> _pollSpotify() async {
    if (!_running || !Config.hasSpotify) return;
    try {
      final now = await SpotifyApi.nowPlaying();
      if (now == null) return; // no conectado
      final key = '${now.id}|${now.playing}';
      final stale = DateTime.now().difference(_lastTrackSent) > const Duration(minutes: 2);
      if (key == _lastTrackKey && !stale) return;
      final ok = await _rpc('push_track', {
        'p_name': now.name,
        'p_artist': now.artist,
        'p_image': now.image,
        'p_url': now.url,
        'p_progress': now.progressMs,
        'p_duration': now.durationMs,
        'p_playing': now.playing,
      });
      if (ok) {
        _lastTrackKey = key;
        _lastTrackSent = DateTime.now();
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------------

  Future<bool> _rpc(String fn, Map<String, dynamic> args) async {
    try {
      final res = await http
          .post(
            Uri.parse('${Config.supabaseUrl}/rest/v1/rpc/$fn'),
            headers: {
              'apikey': Config.supabaseAnonKey,
              'Authorization': 'Bearer ${Config.supabaseAnonKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'device_key': _deviceKey, ...args}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 400 && res.body.contains('Dispositivo no registrado')) {
        await stop(); // la llave se revocó (cerró sesión en otro lado)
      }
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static double _distance(Position a, Position b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
}
