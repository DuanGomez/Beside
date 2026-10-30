import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/dark_map.dart';

class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  void _open(BuildContext context, [Place? place]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceEditor(place: place)));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final today = DateTime.now();
        final todayEvents = s.events.where((e) => e.at.year == today.year && e.at.month == today.month && e.at.day == today.day).toList();
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 120), children: [
              Row(children: [
                const Expanded(child: Text('Lugares', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6))),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nuevo lugar'),
                ),
              ]),
              const SizedBox(height: 6),
              const Text('Te avisamos cuando alguien de tu círculo llegue o salga de estos lugares.',
                  style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              if (s.places.isEmpty)
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Aún no hay lugares', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    const Text('Marca la casa de cada uno, los trabajos, el gym, la universidad…', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => _open(context), child: const Text('Marcar el primero')),
                  ]),
                )
              else
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: [for (final p in s.places) _PlaceCard(place: p, onTap: () => _open(context, p))],
                ),
              if (todayEvents.isNotEmpty) ...[
                const SectionLabel('Hoy en sus lugares'),
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(children: [
                    for (final e in todayEvents.take(12))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(children: [
                          Avatar(member: s.members[e.userId], size: 28, ring: false),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${s.members[e.userId] == null ? 'Alguien' : s.displayName(s.members[e.userId]!)} ${e.isEnter ? 'llegó a' : 'salió de'} ${e.placeName}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(hour(e.at), style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                        ]),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.onTap});
  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final here = s.lives.values.where((l) => l.placeId == place.id && s.members.containsKey(l.userId)).toList();
    final alerts = [if (place.notifyEnter) 'llegar', if (place.notifyExit) 'salir'].join(' y ');
    return Material(
      color: C.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: here.isNotEmpty ? C.accent : C.border, width: here.isNotEmpty ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PlaceIcon(icon: place.icon),
              const Spacer(),
              if (here.isNotEmpty)
                SizedBox(
                  height: 28,
                  width: 28.0 + (here.length - 1) * 16,
                  child: Stack(children: [
                    for (var i = 0; i < here.length; i++)
                      Positioned(left: i * 16.0, child: Avatar(member: s.members[here[i].userId], size: 28)),
                  ]),
                ),
            ]),
            const Spacer(),
            Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(
              '${alerts.isEmpty ? 'Sin avisos' : 'Avisa al ${alerts.replaceFirst(' y ', ' y al ')}'} · ${place.radius} m',
              maxLines: 2,
              style: const TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Crear o editar un lugar: el centro del mapa es el lugar.
class PlaceEditor extends StatefulWidget {
  const PlaceEditor({super.key, this.place});
  final Place? place;

  @override
  State<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<PlaceEditor> {
  final _map = MapController();
  final _s = AppState.instance;
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late LatLng _center = widget.place != null
      ? LatLng(widget.place!.lat, widget.place!.lng)
      : (_s.myId != null && _s.lives[_s.myId] != null ? LatLng(_s.lives[_s.myId]!.lat, _s.lives[_s.myId]!.lng) : const LatLng(6.2442, -75.5812));
  late double _radius = (widget.place?.radius ?? 100).toDouble();
  late String _icon = widget.place?.icon ?? 'home';
  late bool _enter = widget.place?.notifyEnter ?? true;
  late bool _exit = widget.place?.notifyExit ?? false;
  late String? _circleId = widget.place?.circleId ?? (_s.circles.isNotEmpty ? _s.circles.first.id : null);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.place == null && !_s.demo) _goToMe();
  }

  Future<void> _goToMe() async {
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 15)));
      _moveTo(LatLng(p.latitude, p.longitude));
    } catch (_) {
      final me = _s.myId == null ? null : _s.lives[_s.myId];
      if (me != null) _moveTo(LatLng(me.lat, me.lng));
    }
  }

  void _moveTo(LatLng p) {
    if (!mounted) return;
    setState(() => _center = p);
    _map.move(p, 17);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, 'Ponle un nombre al lugar.');
    if (_circleId == null) return toast(context, 'Primero crea o únete a un círculo.');
    setState(() => _busy = true);
    final data = {
      'circle_id': _circleId,
      'name': _name.text.trim(),
      'icon': _icon,
      'lat': _center.latitude,
      'lng': _center.longitude,
      'radius_m': _radius.round(),
      'notify_enter': _enter,
      'notify_exit': _exit,
    };
    try {
      if (_s.demo) {
        final id = widget.place?.id ?? 'p${DateTime.now().millisecondsSinceEpoch}';
        _s.places
          ..removeWhere((p) => p.id == id)
          ..add(Place({...data, 'id': id}));
        _s.changed();
      } else if (widget.place == null) {
        await db.from('places').insert({...data, 'created_by': db.auth.currentUser!.id});
      } else {
        await db.from('places').update(data).eq('id', widget.place!.id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('¿Borrar ${widget.place!.name}?'),
        content: const Text('Dejarás de recibir avisos de este lugar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger), onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    if (_s.demo) {
      _s.places.removeWhere((p) => p.id == widget.place!.id);
      _s.changed();
    } else {
      await db.from('places').delete().eq('id', widget.place!.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final color = placeIconColors[_icon] ?? C.accent;
    final circles = _s.circles;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.place == null ? 'Nuevo lugar' : 'Editar lugar'),
        actions: [
          if (widget.place != null) IconButton(tooltip: 'Borrar lugar', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded, color: C.danger)),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 280,
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 17,
                backgroundColor: C.map,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onPositionChanged: (camera, _) => setState(() => _center = camera.center),
              ),
              children: [
                darkTiles(),
                CircleLayer(circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radius,
                    useRadiusInMeter: true,
                    color: color.withValues(alpha: 0.16),
                    borderColor: color,
                    borderStrokeWidth: 2,
                  ),
                ]),
              ],
            ),
            IgnorePointer(child: Center(child: PlaceIcon(icon: _icon, size: 40))),
            mapAttribution(),
            Positioned(
              right: 12,
              top: 12,
              child: Material(
                color: C.surface,
                shape: const CircleBorder(side: BorderSide(color: C.border)),
                child: IconButton(tooltip: 'Ir a mi ubicación', onPressed: _goToMe, icon: const Icon(Icons.my_location_rounded, color: C.accent)),
              ),
            ),
            const Positioned(
              left: 12,
              top: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xE6111318), borderRadius: BorderRadius.all(Radius.circular(999))),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('Mueve el mapa para ubicarlo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 24), children: [
            TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nombre (ej. Casa de ella)')),
            const SectionLabel('Ícono'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in placeIcons.keys)
                Semantics(
                  button: true,
                  selected: k == _icon,
                  label: 'Ícono $k',
                  child: GestureDetector(
                    onTap: () => setState(() => _icon = k),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: k == _icon ? C.text : Colors.transparent, width: 2),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: PlaceIcon(icon: k, size: 44),
                    ),
                  ),
                ),
            ]),
            const SectionLabel('Tamaño de la zona'),
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Column(children: [
                Row(children: [
                  const Expanded(child: Text('Radio', style: TextStyle(fontWeight: FontWeight.w800))),
                  Text('${_radius.round()} m', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
                  const SizedBox(width: 8),
                ]),
                Slider(min: 40, max: 500, divisions: 46, value: _radius, onChanged: (v) => setState(() => _radius = v)),
                const Padding(
                  padding: EdgeInsets.only(right: 8, bottom: 6),
                  child: Text('Una casa o un local: 60–100 m. Un conjunto, universidad o centro comercial: 150 m o más.',
                      style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            const SectionLabel('Avisos'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Column(children: [
                SwitchListTile(
                  value: _enter,
                  onChanged: (v) => setState(() => _enter = v),
                  title: const Text('Cuando alguien llegue', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                SwitchListTile(
                  value: _exit,
                  onChanged: (v) => setState(() => _exit = v),
                  title: const Text('Cuando alguien salga', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            if (circles.length > 1) ...[
              const SectionLabel('Círculo'),
              DropdownButtonFormField<String>(
                initialValue: _circleId,
                dropdownColor: C.surface,
                items: [for (final c in circles) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _circleId = v),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(onPressed: _busy ? null : _save, child: Text(widget.place == null ? 'Guardar lugar' : 'Guardar cambios')),
          ]),
        ),
      ]),
    );
  }
}
