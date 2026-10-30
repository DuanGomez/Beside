import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/tracking.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'history_screen.dart';
import 'map_screen.dart';
import 'places_screen.dart';
import 'profile_screen.dart';

/// Contenedor con las cuatro secciones y la barra en píldora.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static final _key = GlobalKey<_HomeShellState>();

  /// Ofrece unirse a un círculo cuando llega un enlace de invitación.
  static void showJoin(String code) => _key.currentState?._offerJoin(code);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.instance.latestEvent.addListener(_onEvent);
    final pending = AppState.instance.pendingInviteCode;
    if (pending != null) WidgetsBinding.instance.addPostFrameCallback((_) => _offerJoin(pending));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppState.instance.latestEvent.removeListener(_onEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app: asegurar que el servicio siga encendido
    if (state == AppLifecycleState.resumed) unawaited(Tracking.resumeIfNeeded());
  }

  void _onEvent() {
    final e = AppState.instance.latestEvent.value;
    if (e == null || !mounted) return;
    final s = AppState.instance;
    final who = s.members[e.userId];
    final name = who == null ? 'Alguien' : s.displayName(who);
    toast(context, e.isEnter ? '$name llegó a ${e.placeName} · ${hour(e.at)}' : '$name salió de ${e.placeName} · ${hour(e.at)}');
  }

  Future<void> _offerJoin(String code) async {
    AppState.instance.pendingInviteCode = null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Invitación a un círculo'),
        content: Text('¿Quieres unirte al círculo con el código $code?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unirme')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.rpc('join_circle', params: {'invite_code': code});
      await AppState.instance.refreshCircles();
      if (mounted) toast(context, 'Te uniste al círculo.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: HomeShell._key,
      backgroundColor: C.map,
      body: Stack(children: [
        IndexedStack(index: _tab, children: const [MapScreen(), PlacesScreen(), HistoryScreen(), ProfileScreen()]),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(top: false, child: Center(child: _PillNav(index: _tab, onTap: (i) => setState(() => _tab = i)))),
        ),
      ]),
    );
  }
}

class _PillNav extends StatelessWidget {
  const _PillNav({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.map_rounded, 'Mapa'),
    (Icons.place_rounded, 'Lugares'),
    (Icons.schedule_rounded, 'Historial'),
    (Icons.person_rounded, 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: C.border),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: Semantics(
              button: true,
              selected: i == index,
              label: _items[i].$2,
              child: Material(
                color: i == index ? C.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onTap(i),
                  child: SizedBox(
                    width: 60,
                    height: 48,
                    child: Icon(_items[i].$1, color: i == index ? C.map : C.muted, size: 24),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
