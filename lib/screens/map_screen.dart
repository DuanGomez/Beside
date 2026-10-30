import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/beside_map.dart';
import 'invite_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final _map = BesideMapController();
  final _state = AppState.instance;
  bool _ready = false;
  bool _follow = true;
  bool _centered = false;
  String? _lastSelected;

  // Posiciones que se muestran: se deslizan hacia la nueva en vez de saltar
  late final AnimationController _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..addListener(_onGlide);
  final Map<String, LatLng> _from = {};
  final Map<String, LatLng> _to = {};
  final Map<String, LatLng> _shown = {};
  final Map<String, String> _addressCache = {};
  String? _address;

  // Tu ubicación sale directo del GPS de este celular: te ves al instante
  StreamSubscription<Position>? _gps;
  LatLng? _myPos;

  // Con quién estás ahora mismo, y desde cuándo
  final Set<String> _together = {};
  final Map<String, DateTime> _togetherSince = {};

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
    _syncPositions(animate: false);
    _startGps();
    _loadTogether();
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _gps?.cancel();
    _glide.dispose();
    super.dispose();
  }

  Future<void> _startGps() async {
    if (_state.demo) return;
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) return;
      _gps = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)).listen(
        (pos) {
          if (pos.accuracy > 150) return;
          _myPos = LatLng(pos.latitude, pos.longitude);
          _onState();
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _loadTogether() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('juntos');
      if (raw == null) return;
      final now = DateTime.now();
      (jsonDecode(raw) as Map<String, dynamic>).forEach((id, iso) {
        final at = DateTime.tryParse(iso as String? ?? '');
        // Solo si fue hace poco; si no, seguro se separaron con la app cerrada
        if (at != null && now.difference(at) < const Duration(hours: 14)) _togetherSince.putIfAbsent(id, () => at);
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveTogether() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('juntos', jsonEncode({for (final id in _together) id: _togetherSince[id]?.toIso8601String()}));
    } catch (_) {}
  }

  /// Dónde está cada uno (tú, con el GPS de este celular si lo hay).
  Map<String, LatLng> _targets() {
    final t = {for (final l in _state.lives.values) l.userId: LatLng(l.lat, l.lng)};
    final me = _state.myId;
    if (me != null && _myPos != null) t[me] = _myPos!;
    return t;
  }

  /// Juntos: a menos de 60 m; se separan pasados 120 m (así el GPS no hace parpadear).
  void _updateTogether() {
    final me = _state.myId;
    if (me == null) return;
    final now = DateTime.now();
    final myLive = _state.lives[me];
    final mine = _myPos ?? ((myLive != null && now.difference(myLive.updatedAt) < const Duration(minutes: 15)) ? _to[me] : null);
    if (mine == null) return;
    var changed = false;
    for (final m in _state.others) {
      final l = _state.lives[m.id];
      final theirs = _to[m.id];
      if (l == null || theirs == null) continue;
      var near = false;
      if (now.difference(l.updatedAt) < const Duration(minutes: 15)) {
        final d = const Distance().as(LengthUnit.Meter, mine, theirs);
        near = _together.contains(m.id) ? d < 120 : d < 60;
      }
      if (near) {
        if (_together.add(m.id)) {
          _togetherSince.putIfAbsent(m.id, () => now);
          changed = true;
        }
      } else {
        if (_together.remove(m.id)) changed = true;
        if (_togetherSince.remove(m.id) != null) changed = true;
      }
    }
    if (changed) _saveTogether();
  }

  Live? get _live => _state.selectedId == null ? null : _state.lives[_state.selectedId];

  void _onState() {
    final live = _live;
    if (_state.selectedId != _lastSelected) {
      _lastSelected = _state.selectedId;
      _follow = true;
      _centered = false;
      _address = null;
    }
    _syncPositions(animate: true);
    if (live != null) {
      if (_ready && !_centered) {
        _map.move(_shown[live.userId]!, 16);
        _centered = true;
      }
      if (live.placeId == null) _resolveAddress(live);
    }
    if (mounted) setState(() {});
  }

  void _syncPositions({required bool animate}) {
    var moved = false;
    for (final e in _targets().entries) {
      final id = e.key, target = e.value;
      final current = _shown[id];
      if (current == null || !animate || const Distance().as(LengthUnit.Meter, current, target) > 3000) {
        _shown[id] = target; // lejos o primera vez: sin animación
        _from[id] = target;
        _to[id] = target;
      } else if (_to[id] != target) {
        _to[id] = target;
        moved = true;
      }
    }
    _updateTogether();
    if (moved) {
      _from.addAll(_shown); // arrancar desde donde se ve ahora
      _glide.forward(from: 0);
      final target = _state.selectedId == null ? null : _to[_state.selectedId];
      if (_ready && _follow && _centered && target != null) _map.animateTo(target);
    }
  }

  void _onGlide() {
    final t = Curves.easeInOut.transform(_glide.value);
    _to.forEach((id, b) {
      final a = _from[id] ?? b;
      _shown[id] = LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
    });
    if (mounted) setState(() {});
  }

  Future<void> _resolveAddress(Live live) async {
    if (kIsWeb) return; // el navegador no tiene geocodificación del sistema
    final key = '${live.lat.toStringAsFixed(3)},${live.lng.toStringAsFixed(3)}';
    if (_addressCache.containsKey(key)) {
      _address = _addressCache[key];
      return;
    }
    _addressCache[key] = '';
    try {
      final marks = await Geocoding(locale: const Locale('es', 'CO')).placemarkFromCoordinates(live.lat, live.lng);
      if (marks.isEmpty) return;
      final m = marks.first;
      final parts = [m.thoroughfare ?? m.street, m.subLocality ?? m.locality].where((s) => s != null && s.trim().isNotEmpty).toList();
      _addressCache[key] = parts.join(', ');
      if (mounted) setState(() => _address = _addressCache[key]);
    } catch (_) {}
  }

  Future<void> _recenter() async {
    setState(() => _follow = true);
    final live = _live;
    if (live != null) {
      _map.move(_shown[live.userId] ?? LatLng(live.lat, live.lng), 16.5);
      _centered = true;
    } else {
      try {
        final p = await Geolocator.getLastKnownPosition();
        if (p != null) _map.move(LatLng(p.latitude, p.longitude), 15);
      } catch (_) {}
    }
  }

  void _pickPerson() {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _PeopleSheet(onPick: (id) {
        Navigator.pop(context);
        _state.select(id);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final selected = s.selected;
    final live = _live;
    final place = s.placeById(live?.placeId);
    final top = MediaQuery.paddingOf(context).top;
    final together = selected != null && _together.contains(selected.id);

    return Stack(children: [
      BesideMap(
        controller: _map,
        initialCenter: live != null ? LatLng(live.lat, live.lng) : const LatLng(6.2442, -75.5812),
        initialZoom: live != null ? 16 : 12,
        // El centro del mapa queda sobre la tarjeta de abajo y el logo de Google a la vista
        padding: EdgeInsets.only(top: top + 70, bottom: MediaQuery.paddingOf(context).bottom + 300),
        onReady: () {
          _ready = true;
          _onState();
        },
        onUserGesture: () {
          if (_follow) setState(() => _follow = false);
        },
        onPersonTap: s.select,
        places: s.places,
        highlightPlaceId: place?.id,
        circles: [
          if (live?.accuracy != null && live!.accuracy! > 20)
            MapCircle(
              id: 'precision',
              center: _shown[live.userId] ?? LatLng(live.lat, live.lng),
              radius: live.accuracy!,
              color: hexColor(selected?.color).withValues(alpha: 0.35),
              fill: 0.08,
              stroke: 1,
            ),
        ],
        people: [
          for (final e in _shown.entries)
            if (s.members.containsKey(e.key) && !_together.contains(e.key) && !(e.key == s.myId && _together.isNotEmpty))
              MapPerson(
                id: e.key,
                member: s.members[e.key],
                position: e.value,
                selected: e.key == s.selectedId,
                stale: e.key == s.myId && _myPos != null
                    ? false
                    : DateTime.now().difference(s.lives[e.key]?.updatedAt ?? DateTime(2000)) > const Duration(minutes: 30),
              ),
        ],
        couples: [
          for (final id in _together)
            if (s.myId != null && _shown[s.myId] != null && _shown[id] != null)
              MapCouple(
                id: id,
                a: s.me,
                b: s.members[id],
                position: LatLng((_shown[s.myId]!.latitude + _shown[id]!.latitude) / 2, (_shown[s.myId]!.longitude + _shown[id]!.longitude) / 2),
                selected: id == s.selectedId,
              ),
        ],
      ),

      // Encabezado: "Mi amor está en el Gym"
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: IgnorePointer(
          ignoring: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(18, top + 12, 18, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.55, 1], colors: [C.map, Color(0x00111318)]),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: _pickPerson,
                child: together ? _TogetherAvatars(a: s.me, b: selected) : Avatar(member: selected, size: 54, glow: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _pickPerson,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        together
                            ? 'Tú y ${s.displayName(selected)}'
                            : (selected == null ? 'Tu círculo' : (selected.id == s.myId ? 'Tú estás' : '${s.displayName(selected)} está')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.muted)),
                    Text(together ? (place != null ? 'juntitos en ${place.name}' : 'están juntitos') : _headline(live, place),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 25, height: 1.1, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: together ? C.accent : null)),
                  ]),
                ),
              ),
              _RoundButton(icon: Icons.swap_horiz_rounded, label: 'Cambiar persona', onTap: _pickPerson),
            ]),
          ),
        ),
      ),

      // Centrar en la persona
      Positioned(
        right: 16,
        bottom: 330,
        child: _RoundButton(
          icon: _follow ? Icons.my_location_rounded : Icons.location_searching_rounded,
          label: 'Centrar en el mapa',
          color: _follow ? C.accent : C.text,
          square: true,
          onTap: _recenter,
        ),
      ),

      // Tarjeta inferior
      Positioned(
        left: 12,
        right: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 86,
        child: s.others.isEmpty
            ? _InviteCard(onInvite: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteScreen())))
            : _EverySecond(
                builder: (_) => _StatusCard(
                  live: live,
                  place: place,
                  isMe: selected?.id == s.myId,
                  myLive: s.myId == null ? null : s.lives[s.myId],
                  togetherSince: together ? (_togetherSince[selected.id] ?? DateTime.now()) : null,
                ),
              ),
      ),
    ]);
  }

  String _headline(Live? live, Place? place) {
    if (live == null) return 'sin ubicación aún';
    if (place != null) return 'en ${place.name}';
    if ((live.speed ?? 0) > 2) return 'en camino';
    if (_address != null && _address!.isNotEmpty) return 'cerca de $_address';
    return 'fuera de sus lugares';
  }
}

/// Las dos fotos juntas con corazoncitos que suben, para el encabezado.
class _TogetherAvatars extends StatefulWidget {
  const _TogetherAvatars({required this.a, required this.b});
  final Member? a;
  final Member? b;

  @override
  State<_TogetherAvatars> createState() => _TogetherAvatarsState();
}

class _TogetherAvatarsState extends State<_TogetherAvatars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 58,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, top: 2, child: Avatar(member: widget.a, size: 50)),
        Positioned(left: 32, top: 2, child: Avatar(member: widget.b, size: 50, glow: true)),
        Positioned(
          left: 31,
          top: 36,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.accent, border: Border.all(color: C.map, width: 2.5)),
            child: const Icon(Icons.favorite_rounded, size: 13, color: Colors.white),
          ),
        ),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < 4; i++)
              Builder(builder: (context) {
                final t = (_c.value + i / 4) % 1;
                final fade = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
                return Positioned(
                  left: 36 + i * 4 + math.sin(t * math.pi * 2 + i) * 9,
                  top: 18 - t * 44,
                  child: Opacity(
                    opacity: fade.clamp(0.0, 1.0) * 0.9,
                    child: Icon(Icons.favorite_rounded, size: 9 + i * 2.0, color: i.isEven ? C.accent : const Color(0xFFC9B8F7)),
                  ),
                );
              }),
          ]),
        ),
      ]),
    );
  }
}

/// Redibuja solo su contenido cada segundo ("hace X s", barra de la canción),
/// sin tocar el mapa.
class _EverySecond extends StatefulWidget {
  const _EverySecond({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_EverySecond> createState() => _EverySecondState();
}

class _EverySecondState extends State<_EverySecond> {
  late final Timer _timer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.live, required this.place, required this.isMe, required this.myLive, this.togetherSince});
  final Live? live;
  final Place? place;
  final bool isMe;
  final Live? myLive;
  final DateTime? togetherSince;

  @override
  Widget build(BuildContext context) {
    final l = live;
    if (l == null) {
      return const Panel(
        radius: 28,
        child: Text('Todavía no ha compartido su ubicación. Cuando abra Beside y acepte los permisos, aparecerá aquí.',
            style: TextStyle(color: C.muted, fontWeight: FontWeight.w600, height: 1.4)),
      );
    }
    final age = DateTime.now().difference(l.updatedAt);
    final (dot, label) = age < const Duration(minutes: 3)
        ? (C.green, 'EN VIVO · ${ago(l.updatedAt).toUpperCase()}')
        : age < const Duration(minutes: 30)
            ? (C.amber, 'ACTUALIZADO ${ago(l.updatedAt).toUpperCase()}')
            : (C.danger, 'SIN SEÑAL DESDE ${dayLabel(l.updatedAt) == 'Hoy' ? hour(l.updatedAt).toUpperCase() : '${dayLabel(l.updatedAt).toUpperCase()} ${hour(l.updatedAt).toUpperCase()}'}');

    String title;
    String subtitle;
    final distance = (myLive == null || isMe) ? null : Geolocator.distanceBetween(myLive!.lat, myLive!.lng, l.lat, l.lng);
    final distText = distance == null ? '' : 'a ${km(distance)} de ti';
    if (togetherSince != null) {
      title = 'Juntos desde las ${hour(togetherSince!)}';
      subtitle = 'Llevan ${duration(DateTime.now().difference(togetherSince!))} juntitos';
    } else if (place != null && l.placeSince != null) {
      title = 'Llegó a las ${hour(l.placeSince!)}';
      subtitle = ['Hace ${duration(DateTime.now().difference(l.placeSince!))}', if (distText.isNotEmpty) distText].join(' · ');
    } else if ((l.speed ?? 0) > 1.5) {
      title = 'En movimiento · ${((l.speed ?? 0) * 3.6).round()} km/h';
      subtitle = distText.isEmpty ? 'Precisión ±${(l.accuracy ?? 0).round()} m' : distText;
    } else {
      title = isMe ? 'Así te ve tu círculo' : 'Fuera de sus lugares';
      subtitle = [if (distText.isNotEmpty) distText, 'precisión ±${(l.accuracy ?? 0).round()} m'].join(' · ');
    }
    if (age >= const Duration(minutes: 30)) subtitle = 'Puede tener el celular apagado o sin internet.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: C.border),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 14))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dot, boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.3), spreadRadius: 4)]),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: dot, letterSpacing: 0.5)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 14, color: C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 12),
          BatteryRing(level: l.battery, charging: l.charging),
        ]),
        if (l.hasTrack) ...[
          const SizedBox(height: 14),
          NowPlayingCard(live: l),
        ],
      ]),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.onInvite});
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) => Panel(
        radius: 28,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Invita a tu gente', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Comparte tu código o tu QR para verse en el mapa.', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: onInvite, child: const Text('Invitar'))),
        ]),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.color = C.text, this.square = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool square;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: Material(
          color: C.surface,
          shape: square
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.border))
              : const CircleBorder(side: BorderSide(color: C.border)),
          child: InkWell(
            customBorder: square ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)) : const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 48, height: 48, child: Icon(icon, color: color, size: 22)),
          ),
        ),
      );
}

/// Lista de personas del círculo para elegir a quién ver.
class _PeopleSheet extends StatelessWidget {
  const _PeopleSheet({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text('¿A quién quieres ver?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
        for (final m in s.everyone)
          Builder(builder: (context) {
            final l = s.lives[m.id];
            final place = s.placeById(l?.placeId);
            final status = l == null
                ? 'Sin ubicación todavía'
                : place != null
                    ? 'En ${place.name} · ${ago(l.updatedAt)}'
                    : 'Actualizado ${ago(l.updatedAt)}';
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              leading: Avatar(member: m, size: 46),
              title: Text(m.id == s.myId ? 'Tú' : s.displayName(m), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              subtitle: Text(status, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
              trailing: l?.battery == null ? null : Text('${l!.battery}%', style: const TextStyle(fontWeight: FontWeight.w800, color: C.muted)),
              selected: m.id == s.selectedId,
              onTap: () => onPick(m.id),
            );
          }),
      ]),
    );
  }
}
