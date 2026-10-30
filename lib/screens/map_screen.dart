import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/dark_map.dart';
import 'invite_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final _map = MapController();
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

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
    _syncPositions(animate: false);
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _glide.dispose();
    super.dispose();
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
    for (final l in _state.lives.values) {
      final target = LatLng(l.lat, l.lng);
      final current = _shown[l.userId];
      if (current == null || !animate || const Distance().as(LengthUnit.Meter, current, target) > 3000) {
        _shown[l.userId] = target; // lejos o primera vez: sin animación
        _from[l.userId] = target;
        _to[l.userId] = target;
      } else if (_to[l.userId] != target) {
        _to[l.userId] = target;
        moved = true;
      }
    }
    if (moved) {
      _from.addAll(_shown); // arrancar desde donde se ve ahora
      _glide.forward(from: 0);
    } else if (!_glide.isAnimating) {
      _followSelected();
    }
  }

  void _onGlide() {
    final t = Curves.easeInOut.transform(_glide.value);
    _to.forEach((id, b) {
      final a = _from[id] ?? b;
      _shown[id] = LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
    });
    _followSelected();
    if (mounted) setState(() {});
  }

  void _followSelected() {
    final id = _state.selectedId;
    final p = id == null ? null : _shown[id];
    if (_ready && _follow && _centered && p != null) _map.move(p, _map.camera.zoom);
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

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: live != null ? LatLng(live.lat, live.lng) : const LatLng(6.2442, -75.5812),
          initialZoom: live != null ? 16 : 12,
          backgroundColor: C.map,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () {
            _ready = true;
            _onState();
          },
          onPositionChanged: (camera, hasGesture) {
            if (hasGesture && _follow) setState(() => _follow = false);
          },
        ),
        children: [
          darkTiles(),
          placeCircles(s.places, highlightId: place?.id),
          placeMarkers(s.places),
          if (live?.accuracy != null && live!.accuracy! > 20)
            CircleLayer(circles: [
              CircleMarker(
                point: _shown[live.userId] ?? LatLng(live.lat, live.lng),
                radius: live.accuracy!,
                useRadiusInMeter: true,
                color: hexColor(selected?.color).withValues(alpha: 0.08),
                borderColor: hexColor(selected?.color).withValues(alpha: 0.3),
                borderStrokeWidth: 1,
              ),
            ]),
          MarkerLayer(markers: [
            for (final l in s.lives.values)
              if (s.members.containsKey(l.userId))
                Marker(
                  point: _shown[l.userId] ?? LatLng(l.lat, l.lng),
                  width: l.userId == s.selectedId ? 120 : 46,
                  height: l.userId == s.selectedId ? 120 : 46,
                  child: GestureDetector(
                    onTap: () => s.select(l.userId),
                    child: PersonMarker(
                      member: s.members[l.userId],
                      selected: l.userId == s.selectedId,
                      stale: DateTime.now().difference(l.updatedAt) > const Duration(minutes: 30),
                    ),
                  ),
                ),
          ]),
        ],
      ),
      mapAttribution(),

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
              GestureDetector(onTap: _pickPerson, child: Avatar(member: selected, size: 54, glow: true)),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _pickPerson,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(selected == null ? 'Tu círculo' : (selected.id == s.myId ? 'Tú estás' : '${s.displayName(selected)} está'),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.muted)),
                    Text(_headline(live, place), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 25, height: 1.1, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
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
                builder: (_) => _StatusCard(live: live, place: place, isMe: selected?.id == s.myId, myLive: s.myId == null ? null : s.lives[s.myId]),
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
  const _StatusCard({required this.live, required this.place, required this.isMe, required this.myLive});
  final Live? live;
  final Place? place;
  final bool isMe;
  final Live? myLive;

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
    if (place != null && l.placeSince != null) {
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
