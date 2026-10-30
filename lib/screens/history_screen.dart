import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../demo.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/beside_map.dart';

/// Recorridos de los últimos 30 días, día por día.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _s = AppState.instance;
  final _map = BesideMapController();
  String? _person;
  DateTime _day = DateTime.now();
  bool _loading = false;
  List<_Point> _points = [];
  List<PlaceEvent> _events = [];
  String? _loadedKey;

  String? get _personId => _person ?? _s.selectedId ?? _s.myId;

  @override
  void initState() {
    super.initState();
    _s.addListener(_maybeLoad);
    _maybeLoad();
  }

  @override
  void dispose() {
    _s.removeListener(_maybeLoad);
    super.dispose();
  }

  void _maybeLoad() {
    final key = '$_personId|${_day.year}-${_day.month}-${_day.day}';
    if (key != _loadedKey && _personId != null) _load(key);
  }

  Future<void> _load(String key) async {
    _loadedKey = key;
    setState(() => _loading = true);
    final start = DateTime(_day.year, _day.month, _day.day);
    final end = start.add(const Duration(days: 1));
    final id = _personId!;
    try {
      List<Map<String, dynamic>> rows;
      List<PlaceEvent> events;
      if (_s.demo) {
        rows = Demo.history(id, start);
        events = _s.events.where((e) => e.userId == id && !e.at.isBefore(start) && e.at.isBefore(end)).toList();
      } else {
        rows = [];
        // Supabase entrega máximo 1000 filas por consulta: se pide por páginas
        for (var from = 0;; from += 1000) {
          final page = await db
              .from('location_points')
              .select('lat, lng, speed, accuracy, recorded_at')
              .eq('user_id', id)
              .gte('recorded_at', start.toUtc().toIso8601String())
              .lt('recorded_at', end.toUtc().toIso8601String())
              .order('recorded_at')
              .range(from, from + 999);
          rows.addAll(page);
          if (page.length < 1000) break;
        }
        final ev = await db
            .from('place_events')
            .select()
            .eq('user_id', id)
            .gte('at', start.toUtc().toIso8601String())
            .lt('at', end.toUtc().toIso8601String())
            .order('at');
        events = ev.map(PlaceEvent.new).toList();
      }
      if (key != _loadedKey || !mounted) return;
      setState(() {
        _points = rows
            .map((r) => _Point(LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()), DateTime.parse(r['recorded_at'] as String).toLocal(),
                (r['speed'] as num?)?.toDouble() ?? 0))
            .toList();
        _events = events..sort((a, b) => a.at.compareTo(b.at));
        _loading = false;
      });
      _fit();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e));
      }
    }
  }

  void _fit() {
    if (_points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _map.fit(_points.map((e) => e.p).toList(), padding: 36);
      } catch (_) {}
    });
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
      helpText: 'Elige un día',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(surface: C.surface)),
        child: child!,
      ),
    );
    if (d != null) {
      setState(() => _day = d);
      _maybeLoad();
    }
  }

  ({double distance, Duration moving}) _stats() {
    var distance = 0.0;
    var moving = Duration.zero;
    const calc = Distance();
    for (var i = 1; i < _points.length; i++) {
      final a = _points[i - 1], b = _points[i];
      final d = calc.as(LengthUnit.Meter, a.p, b.p);
      final dt = b.t.difference(a.t);
      // Tramos con desplazamiento real (no el temblor del GPS estando quieta)
      if (d > 15 && dt < const Duration(minutes: 15)) {
        distance += d;
        if (d / (dt.inSeconds == 0 ? 1 : dt.inSeconds) > 0.7) moving += dt;
      }
    }
    return (distance: distance, moving: moving);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final person = _personId == null ? null : _s.members[_personId];
        final stats = _stats();
        final visits = _visits();
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 120), children: [
              const Text('Historial', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final m in _s.everyone)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        selected: m.id == _personId,
                        onTap: () {
                          setState(() => _person = m.id);
                          _maybeLoad();
                        },
                        leading: Avatar(member: m, size: 30, ring: false),
                        label: m.id == _s.myId ? 'Tú' : _s.displayName(m),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                for (final (label, offset) in [('Hoy', 0), ('Ayer', 1)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Chip(
                      selected: dayLabel(_day) == label,
                      label: label,
                      onTap: () {
                        setState(() => _day = DateTime.now().subtract(Duration(days: offset)));
                        _maybeLoad();
                      },
                    ),
                  ),
                _Chip(
                  selected: dayLabel(_day) != 'Hoy' && dayLabel(_day) != 'Ayer',
                  label: dayLabel(_day) != 'Hoy' && dayLabel(_day) != 'Ayer' ? dayLabel(_day) : 'Otro día',
                  leading: const Icon(Icons.calendar_month_rounded, size: 18),
                  onTap: _pickDay,
                ),
              ]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: SizedBox(
                  height: 260,
                  child: Stack(children: [
                    BesideMap(
                      controller: _map,
                      initialCenter: const LatLng(6.2442, -75.5812),
                      initialZoom: 13,
                      onReady: _fit,
                      places: _s.places,
                      lines: [
                        if (_points.length > 1) ...[
                          MapLine(id: 'halo', points: _points.map((e) => e.p).toList(), color: hexColor(person?.color).withValues(alpha: 0.2), width: 10),
                          MapLine(id: 'ruta', points: _points.map((e) => e.p).toList(), color: hexColor(person?.color), width: 5),
                        ],
                      ],
                      startDot: _points.length > 1 ? _points.first.p : null,
                      people: [
                        if (_points.isNotEmpty && person != null) MapPerson(id: person.id, member: person, position: _points.last.p),
                      ],
                    ),
                    if (_loading) const Center(child: CircularProgressIndicator()),
                    if (!_loading && _points.isEmpty)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.border)),
                          child: const Text('Sin recorridos este día', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Wrap(spacing: 6, children: [
                        _Pill(km(stats.distance)),
                        _Pill('${visits.length} ${visits.length == 1 ? 'lugar' : 'lugares'}'),
                        if (stats.moving > Duration.zero) _Pill('${duration(stats.moving)} en movimiento'),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SectionLabel('Línea de tiempo'),
              if (visits.isEmpty)
                Panel(
                  child: Text(
                    _points.isEmpty
                        ? 'Aquí verás a dónde fue y cuánto tiempo estuvo en cada lugar marcado.'
                        : 'Se movió, pero no pasó por ningún lugar marcado. Marca sus lugares para verlos aquí.',
                    style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                )
              else
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(children: [
                    for (var i = visits.length - 1; i >= 0; i--) _VisitRow(visit: visits[i], last: i == 0),
                  ]),
                ),
              const SizedBox(height: 14),
              const Text('Los recorridos se guardan 30 días y luego se borran solos.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
      },
    );
  }

  /// Visitas a lugares: une cada llegada con su salida.
  List<_Visit> _visits() {
    final out = <_Visit>[];
    final open = <String, _Visit>{};
    for (final e in _events) {
      final key = e.placeId ?? e.placeName;
      if (e.isEnter) {
        final v = _Visit(e.placeName, _s.placeById(e.placeId)?.icon ?? 'pin', e.at, null);
        open[key] = v;
        out.add(v);
      } else if (open[key] != null) {
        open.remove(key)!.end = e.at;
      } else {
        // Salió de un lugar donde estaba desde antes de este día
        out.add(_Visit(e.placeName, _s.placeById(e.placeId)?.icon ?? 'pin', null, e.at));
      }
    }
    return out;
  }
}

class _Point {
  _Point(this.p, this.t, this.speed);
  final LatLng p;
  final DateTime t;
  final double speed;
}

class _Visit {
  _Visit(this.name, this.icon, this.start, this.end);
  final String name;
  final String icon;
  final DateTime? start;
  DateTime? end;
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.visit, required this.last});
  final _Visit visit;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final start = visit.start, end = visit.end;
    final when = start != null && end != null
        ? '${hour(start)} – ${hour(end)} · ${duration(end.difference(start))}'
        : start != null
            ? 'Desde ${hour(start)} · sigue ahí'
            : 'Hasta ${hour(end!)}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: C.border))),
      child: Row(children: [
        PlaceIcon(icon: visit.icon, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(visit.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            Text(when, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.selected, required this.label, required this.onTap, this.leading});
  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? C.accent.withValues(alpha: 0.16) : C.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? C.accent : C.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(leading == null ? 16 : 6, 6, 16, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? C.accent : C.text)),
            ]),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xE6221C25), borderRadius: BorderRadius.circular(999), border: Border.all(color: C.border)),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );
}
