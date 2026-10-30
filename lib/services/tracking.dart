import 'package:beside/util/platform.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tracker.dart';

/// Punto de entrada del servicio de Android (corre en su propio isolate).
@pragma('vm:entry-point')
void startTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(_TrackerTaskHandler());
}

class _TrackerTaskHandler extends TaskHandler {
  final _tracker = Tracker();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _tracker.start();

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) => _tracker.stop();

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

/// Enciende o apaga el compartir ubicación en cada plataforma.
class Tracking {
  static Tracker? _iosTracker;
  static const _kSharing = 'sharing';

  static void init() {
    if (!isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'beside_ubicacion',
        channelName: 'Compartir ubicación',
        channelDescription: 'Aparece mientras Beside comparte tu ubicación con tu círculo.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> isSharing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSharing) ?? false;
  }

  /// Registra este celular (una sola vez por cuenta) para publicar sin sesión.
  static Future<void> ensureDeviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (prefs.getString('device_key') != null && prefs.getString('device_user') == uid) return;
    final key = await Supabase.instance.client.rpc('register_device', params: {'device_platform': platformName});
    await prefs.setString('device_key', key as String);
    await prefs.setString('device_user', uid);
  }

  static Future<void> start() async {
    await ensureDeviceKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSharing, true);

    if (isAndroid) {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 717,
          serviceTypes: [ForegroundServiceTypes.location],
          notificationTitle: 'Compartiendo tu ubicación',
          notificationText: 'Tu círculo te ve en el mapa. Toca para abrir Beside.',
          callback: startTrackingCallback,
        );
      }
    } else {
      _iosTracker ??= Tracker();
      await _iosTracker!.start();
    }
  }

  /// Al abrir la app: si estaba compartiendo, asegurar que siga activo.
  static Future<void> resumeIfNeeded() async {
    if (await isSharing()) await start();
  }

  static Future<void> stop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSharing, false);
    if (isAndroid) {
      await FlutterForegroundTask.stopService();
    } else {
      await _iosTracker?.stop();
      _iosTracker = null;
    }
  }

  /// Al cerrar sesión: apagar y olvidar la llave del dispositivo.
  static Future<void> forget() async {
    await stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_key');
    await prefs.remove('device_user');
  }
}
