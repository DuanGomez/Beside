import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'demo.dart';
import 'util/platform.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding.dart';
import 'services/app_state.dart';
import 'services/tracking.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isAndroid) FlutterForegroundTask.initCommunicationPort();
  await initializeDateFormatting('es');
  Intl.defaultLocale = 'es';
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.bg,
  ));
  if (Config.demo) {
    Demo.seed();
  } else if (Config.isConfigured) {
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
  }
  Tracking.init();
  runApp(const BesideApp());
}

class BesideApp extends StatelessWidget {
  const BesideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beside',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Config.demo ? const HomeShell() : (Config.isConfigured ? const Gate() : const _MissingConfig()),
      // En el navegador (vista previa) se muestra con tamaño de celular
      builder: kIsWeb
          ? (context, child) => ColoredBox(
                color: const Color(0xFF0A090B),
                child: Center(
                  child: Container(
                    width: 400,
                    height: 860,
                    margin: const EdgeInsets.all(12),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(44),
                      border: Border.all(color: const Color(0xFF2A2230), width: 6),
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(size: const Size(388, 848), padding: const EdgeInsets.only(top: 28, bottom: 12)),
                      child: child!,
                    ),
                  ),
                ),
              )
          : null,
    );
  }
}

enum Stage { loading, signedOut, profile, circle, permissions, home }

/// Decide qué pantalla mostrar según la cuenta y lo que falta configurar.
class Gate extends StatefulWidget {
  const Gate({super.key});

  static GateState of(BuildContext context) => context.findAncestorStateOfType<GateState>()!;

  @override
  State<Gate> createState() => GateState();
}

class GateState extends State<Gate> {
  Stage _stage = Stage.loading;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _auth = db.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.signedOut || s.event == AuthChangeEvent.initialSession) {
        refresh();
      }
    });
    _listenLinks();
  }

  @override
  void dispose() {
    _auth?.cancel();
    _links?.cancel();
    super.dispose();
  }

  /// Enlaces de invitación: beside://join/BSD-4K7Q
  Future<void> _listenLinks() async {
    final links = AppLinks();
    void handle(Uri uri) {
      final code = inviteCodeFrom(uri.toString());
      if (code == null) return;
      AppState.instance.pendingInviteCode = code;
      if (_stage == Stage.home) {
        HomeShell.showJoin(code);
      } else {
        refresh();
      }
    }

    try {
      final initial = await links.getInitialLink();
      if (initial != null) handle(initial);
    } catch (_) {}
    _links = links.uriLinkStream.listen(handle);
  }

  Future<void> refresh() async {
    final user = db.auth.currentUser;
    if (user == null) {
      await AppState.instance.stop();
      if (mounted) setState(() => _stage = Stage.signedOut);
      return;
    }
    try {
      final profile = await db.from('profiles').select('name').eq('id', user.id).maybeSingle();
      final circles = await db.from('circle_members').select('circle_id').eq('user_id', user.id);
      final prefs = await SharedPreferences.getInstance();
      final Stage next;
      if (profile == null || (profile['name'] as String? ?? '').trim().isEmpty) {
        next = Stage.profile;
      } else if (circles.isEmpty) {
        next = Stage.circle;
      } else if (prefs.getBool('onboarded_${user.id}') != true) {
        next = Stage.permissions;
      } else {
        next = Stage.home; // una invitación pendiente se ofrece al entrar
      }
      if (next == Stage.home) {
        await AppState.instance.start();
        unawaited(Tracking.resumeIfNeeded());
      }
      if (mounted) setState(() => _stage = next);
    } catch (_) {
      // Sin internet: si ya estaba configurado, entrar igual
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _stage = prefs.getBool('onboarded_${user.id}') == true ? Stage.home : Stage.profile);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (_stage) {
      Stage.loading => const _Splash(),
      Stage.signedOut => const WelcomeScreen(),
      Stage.profile => const ProfileSetupScreen(),
      Stage.circle => const CircleSetupScreen(),
      Stage.permissions => const PermissionsScreen(),
      Stage.home => const HomeShell(),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(_stage), child: child));
  }
}

/// Saca el código de un enlace o texto: "beside://join/BSD-4K7Q", "BSD-4K7Q" o "4K7Q".
String? inviteCodeFrom(String raw) {
  final text = raw.trim().toUpperCase();
  final m = RegExp(r'BSD-?([A-Z0-9]{4})').firstMatch(text);
  if (m != null) return 'BSD-${m.group(1)}';
  if (RegExp(r'^[A-Z0-9]{4}$').hasMatch(text)) return 'BSD-$text';
  return null;
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: BesideLogo(size: 76)),
      );
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Falta configurar Supabase.\nCompila con --dart-define=SUPABASE_URL=... y --dart-define=SUPABASE_ANON_KEY=... (ver README).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: C.muted),
            ),
          ),
        ),
      );
}
