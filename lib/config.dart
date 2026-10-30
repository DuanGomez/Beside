/// Valores que se inyectan al compilar con --dart-define (ver README).
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const spotifyClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');

  /// Página donde se descarga la app (se incluye al invitar a alguien).
  static const downloadUrl = String.fromEnvironment(
    'DOWNLOAD_URL',
    defaultValue: 'https://github.com/DuanGomez/Beside/releases/latest',
  );

  /// Descarga directa del APK más reciente y versión web (para iPhone).
  static const apkUrl = 'https://github.com/DuanGomez/Beside/releases/latest/download/Beside.apk';
  static const webUrl = 'https://duangomez.github.io/Beside/';
  static const latestReleaseApi = 'https://api.github.com/repos/DuanGomez/Beside/releases/latest';

  /// Versión de esta compilación (la etiqueta, p. ej. v1.1.0). Vacía en desarrollo.
  static const appVersion = String.fromEnvironment('APP_VERSION');

  /// Vista previa con datos de ejemplo (sin cuenta ni base de datos).
  static const demo = bool.fromEnvironment('DEMO');

  static const spotifyRedirect = 'beside-spotify://callback';
  static const ntfyServer = 'ntfy.sh';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get hasSpotify => spotifyClientId.isNotEmpty;
}
