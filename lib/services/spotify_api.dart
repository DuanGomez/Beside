import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class NowPlaying {
  NowPlaying({
    required this.id,
    required this.name,
    required this.artist,
    required this.image,
    required this.url,
    required this.progressMs,
    required this.durationMs,
    required this.playing,
  });

  final String? id;
  final String? name;
  final String? artist;
  final String? image;
  final String? url;
  final int? progressMs;
  final int? durationMs;
  final bool playing;
}

/// Spotify con PKCE: no necesita secreto; los tokens viven solo en este celular.
class SpotifyApi {
  static const _scopes = 'user-read-currently-playing user-read-playback-state';
  static const _kRefresh = 'spotify_refresh';
  static const _kAccess = 'spotify_access';
  static const _kExpires = 'spotify_expires';

  static Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_kRefresh) != null;
  }

  /// Abre el inicio de sesión de Spotify y guarda los tokens.
  static Future<void> connect() async {
    final verifier = _randomString(64);
    final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final url = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': Config.spotifyClientId,
      'response_type': 'code',
      'redirect_uri': Config.spotifyRedirect,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'scope': _scopes,
    });
    final result = await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: 'beside-spotify');
    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) throw Exception('Spotify no autorizó la conexión');

    final res = await http.post(Uri.parse('https://accounts.spotify.com/api/token'), body: {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': Config.spotifyRedirect,
      'client_id': Config.spotifyClientId,
      'code_verifier': verifier,
    });
    if (res.statusCode != 200) throw Exception('No se pudo conectar Spotify');
    await _saveTokens(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRefresh);
    await prefs.remove(_kAccess);
    await prefs.remove(_kExpires);
  }

  /// Canción actual, o null si Spotify no está conectado.
  static Future<NowPlaying?> nowPlaying() async {
    final token = await _accessToken();
    if (token == null) return null;
    final res = await http.get(
      Uri.parse('https://api.spotify.com/v1/me/player/currently-playing?additional_types=track,episode'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 204 || res.statusCode == 202 || res.body.isEmpty) {
      return NowPlaying(id: null, name: null, artist: null, image: null, url: null, progressMs: null, durationMs: null, playing: false);
    }
    if (res.statusCode == 401) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAccess);
      return null;
    }
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final item = json['item'] as Map<String, dynamic>?;
    if (item == null) {
      return NowPlaying(id: null, name: null, artist: null, image: null, url: null, progressMs: null, durationMs: null, playing: false);
    }
    final artists = (item['artists'] as List?)?.map((a) => a['name']).join(', ') ?? (item['show']?['name'] as String?);
    final images = (item['album']?['images'] ?? item['images']) as List?;
    return NowPlaying(
      id: item['id'] as String?,
      name: item['name'] as String?,
      artist: artists,
      image: images != null && images.isNotEmpty ? images.first['url'] as String? : null,
      url: item['external_urls']?['spotify'] as String?,
      progressMs: json['progress_ms'] as int?,
      durationMs: item['duration_ms'] as int?,
      playing: json['is_playing'] == true,
    );
  }

  static Future<String?> _accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final refresh = prefs.getString(_kRefresh);
    if (refresh == null) return null;
    final access = prefs.getString(_kAccess);
    final expires = prefs.getInt(_kExpires) ?? 0;
    if (access != null && DateTime.now().millisecondsSinceEpoch < expires - 60000) return access;

    final res = await http.post(Uri.parse('https://accounts.spotify.com/api/token'), body: {
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
      'client_id': Config.spotifyClientId,
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode == 400 && res.body.contains('invalid_grant')) {
      await disconnect(); // permiso revocado desde Spotify
      return null;
    }
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    await _saveTokens(json, keepRefresh: refresh);
    return json['access_token'] as String?;
  }

  static Future<void> _saveTokens(Map<String, dynamic> json, {String? keepRefresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, json['access_token'] as String);
    await prefs.setInt(_kExpires, DateTime.now().millisecondsSinceEpoch + ((json['expires_in'] as int? ?? 3600) * 1000));
    final refresh = (json['refresh_token'] as String?) ?? keepRefresh;
    if (refresh != null) await prefs.setString(_kRefresh, refresh);
  }

  static String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
