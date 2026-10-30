import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;

class Member {
  Member({required this.id, required this.name, this.avatarUrl, required this.color});

  factory Member.fromMap(Map<String, dynamic> m) => Member(
        id: m['id'] as String,
        name: (m['name'] as String?)?.trim().isNotEmpty == true ? m['name'] as String : 'Sin nombre',
        avatarUrl: m['avatar_url'] as String?,
        color: (m['color'] as String?) ?? '#F2789A',
      );

  final String id;
  final String name;
  final String? avatarUrl;
  final String color;

  String get initial => name.isEmpty ? '?' : name.characters.first.toUpperCase();
}

class Live {
  Live(this.m);
  final Map<String, dynamic> m;

  String get userId => m['user_id'] as String;
  double get lat => (m['lat'] as num).toDouble();
  double get lng => (m['lng'] as num).toDouble();
  double? get accuracy => (m['accuracy'] as num?)?.toDouble();
  double? get speed => (m['speed'] as num?)?.toDouble();
  int? get battery => m['battery'] as int?;
  bool get charging => m['charging'] == true;
  String? get placeId => m['place_id'] as String?;
  DateTime? get placeSince => _date(m['place_since']);
  DateTime get updatedAt => _date(m['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);

  String? get trackName => m['track_name'] as String?;
  String? get trackArtist => m['track_artist'] as String?;
  String? get trackImage => m['track_image'] as String?;
  String? get trackUrl => m['track_url'] as String?;
  int? get trackProgress => m['track_progress_ms'] as int?;
  int? get trackDuration => m['track_duration_ms'] as int?;
  bool get trackPlaying => m['track_playing'] == true;
  DateTime? get trackAt => _date(m['track_at']);

  /// Hay una canción sonando y el dato es reciente.
  bool get hasTrack =>
      trackPlaying && trackName != null && trackAt != null && DateTime.now().difference(trackAt!) < const Duration(minutes: 8);

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
}

class Place {
  Place(this.m);
  final Map<String, dynamic> m;

  String get id => m['id'] as String;
  String get circleId => m['circle_id'] as String;
  String get name => m['name'] as String;
  String get icon => m['icon'] as String? ?? 'pin';
  double get lat => (m['lat'] as num).toDouble();
  double get lng => (m['lng'] as num).toDouble();
  int get radius => m['radius_m'] as int? ?? 100;
  bool get notifyEnter => m['notify_enter'] == true;
  bool get notifyExit => m['notify_exit'] == true;
}

class Circle {
  Circle({required this.id, required this.name, required this.code});
  final String id;
  final String name;
  final String code;
}

class PlaceEvent {
  PlaceEvent(this.m);
  final Map<String, dynamic> m;
  int get id => m['id'] as int;
  String get userId => m['user_id'] as String;
  String? get placeId => m['place_id'] as String?;
  String get placeName => m['place_name'] as String;
  bool get isEnter => m['kind'] == 'enter';
  DateTime get at => DateTime.parse(m['at'] as String).toLocal();
}

/// Todo lo que la app muestra, sincronizado en tiempo real con Supabase.
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  final Map<String, Member> members = {};
  final Map<String, Live> lives = {};
  final List<Place> places = [];
  final List<Circle> circles = [];
  final List<PlaceEvent> events = [];
  final Map<String, String> nicknames = {};
  String? selectedId;
  String? pendingInviteCode;

  /// Último aviso que llegó con la app abierta (para mostrar un banner).
  final ValueNotifier<PlaceEvent?> latestEvent = ValueNotifier(null);

  final List<StreamSubscription> _subs = [];
  bool _started = false;
  int? _lastEventId;

  bool demo = false;
  String? get myId => demo ? 'me' : db.auth.currentUser?.id;
  Member? get me => myId == null ? null : members[myId];

  /// Personas que no soy yo, en orden de nombre.
  List<Member> get others => members.values.where((m) => m.id != myId).toList()..sort((a, b) => displayName(a).compareTo(displayName(b)));

  List<Member> get everyone => [if (me != null) me!, ...others];

  Member? get selected => selectedId == null ? null : members[selectedId];

  String displayName(Member m) => nicknames[m.id] ?? m.name;

  Place? placeById(String? id) {
    if (id == null) return null;
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> start() async {
    if (_started || demo) return;
    _started = true;
    await _loadNicknames();
    await refreshCircles();

    _subs.add(db.from('profiles').stream(primaryKey: ['id']).listen((rows) {
      members
        ..clear()
        ..addEntries(rows.map((r) => MapEntry(r['id'] as String, Member.fromMap(r))));
      selectedId ??= others.isNotEmpty ? others.first.id : myId;
      if (selectedId != null && !members.containsKey(selectedId)) selectedId = others.isNotEmpty ? others.first.id : myId;
      notifyListeners();
    }));

    _subs.add(db.from('live_locations').stream(primaryKey: ['user_id']).listen((rows) {
      lives
        ..clear()
        ..addEntries(rows.map((r) => MapEntry(r['user_id'] as String, Live(r))));
      notifyListeners();
    }));

    _subs.add(db.from('places').stream(primaryKey: ['id']).order('name', ascending: true).listen((rows) {
      places
        ..clear()
        ..addAll(rows.map(Place.new));
      notifyListeners();
    }));

    _subs.add(db.from('place_events').stream(primaryKey: ['id']).order('at', ascending: false).limit(60).listen((rows) {
      final list = rows.map(PlaceEvent.new).toList();
      events
        ..clear()
        ..addAll(list);
      if (list.isNotEmpty) {
        final newest = list.first;
        if (_lastEventId != null && newest.id != _lastEventId && newest.userId != myId) latestEvent.value = newest;
        _lastEventId = newest.id;
      }
      notifyListeners();
    }));

    _subs.add(db.from('circle_members').stream(primaryKey: ['circle_id', 'user_id']).listen((_) => refreshCircles()));
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _started = false;
    members.clear();
    lives.clear();
    places.clear();
    circles.clear();
    events.clear();
    selectedId = null;
    _lastEventId = null;
  }

  Future<void> refreshCircles() async {
    if (demo) return notifyListeners();
    final rows = await db.from('circles').select('id, name, code').order('created_at');
    circles
      ..clear()
      ..addAll(rows.map((r) => Circle(id: r['id'] as String, name: r['name'] as String, code: r['code'] as String)));
    notifyListeners();
  }

  /// Avisa a las pantallas que algo cambió (lo usa el modo de prueba).
  void changed() => notifyListeners();

  void select(String id) {
    selectedId = id;
    notifyListeners();
  }

  Future<void> setNickname(String userId, String? nickname) async {
    final prefs = await SharedPreferences.getInstance();
    if (nickname == null || nickname.trim().isEmpty) {
      nicknames.remove(userId);
      await prefs.remove('nick_$userId');
    } else {
      nicknames[userId] = nickname.trim();
      await prefs.setString('nick_$userId', nickname.trim());
    }
    notifyListeners();
  }

  Future<void> _loadNicknames() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith('nick_'))) {
      nicknames[k.substring(5)] = prefs.getString(k)!;
    }
  }
}
