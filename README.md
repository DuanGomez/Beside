# Beside

App para ver en tiempo real dónde está tu gente: la ubicación en el mapa, su batería, la canción que suena en su Spotify, avisos cuando llegan o salen de lugares marcados e historial de recorridos de 30 días.

Hecha con Flutter para Android y iPhone. Funciona gratis con Supabase, Esri y ntfy.

## Cómo funciona

- **Compartir ubicación que no se cae.**
  - En Android corre como servicio en primer plano: sigue vivo con la app cerrada y arranca solo al prender el celular.
  - En iPhone usa la ubicación en segundo plano.
  - Publica con una llave propia del dispositivo, así nunca se detiene porque la sesión venció.
- **Precisión.**
  - Usa el GPS más preciso mientras la persona se mueve y baja la frecuencia cuando está quieta.
  - Descarta lecturas imprecisas y saltos imposibles.
  - Guarda los puntos sin internet y los envía después.
- **Lugares.** La llegada y la salida se detectan en el servidor, con un margen de tolerancia para que el GPS no dispare avisos falsos.
- **Avisos.** Cada llegada o salida se envía por [ntfy](https://ntfy.sh), una app gratis para iPhone y Android.
- **Limpieza automática.** Todos los días se borran los recorridos y avisos de más de 30 días, para no pasarse nunca del plan gratis.
- **Spotify.** Se conecta con PKCE: la canción la publica el propio celular y los tokens no salen de él.

## Configuración (una sola vez)

### 1. Supabase (base de datos gratis)

1. Crea un proyecto en [supabase.com](https://supabase.com).
2. En **SQL Editor**, pega todo [supabase/schema.sql](supabase/schema.sql) y dale **Run**.
3. En **Authentication → Sign In / Providers → Email**, desactiva **Confirm email**.
4. En **Project Settings → API**, copia la **Project URL** y la **anon/publishable key**.

### 2. Spotify (opcional)

1. Entra a [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) y crea una app, con la **Web API** marcada.
2. En **Redirect URIs** agrega `beside-spotify://callback`.
3. En **User Management**, agrega el correo de Spotify de cada persona que vaya a conectar su cuenta. En modo desarrollo se permiten hasta 25.
4. Copia el **Client ID**.

### 3. Variables en GitHub

En **Settings → Secrets and variables → Actions → Variables**, crea estas variables:

| Variable | Valor |
|---|---|
| `SUPABASE_URL` | La Project URL |
| `SUPABASE_ANON_KEY` | La anon/publishable key, que es pública por diseño |
| `SPOTIFY_CLIENT_ID` | El Client ID de Spotify |

Los secretos `ANDROID_KEYSTORE_BASE64` y `ANDROID_KEY_PASSWORD` firman el APK. Sin la misma firma, las actualizaciones no se instalan encima de la versión anterior.

### 4. Compilar

Sube una etiqueta, por ejemplo `git tag v1.0.0 && git push --tags`, o ejecuta **Actions → Compilar app → Run workflow**.

La app queda en **Releases**: `Beside.apk` para Android y `Beside.ipa` para iPhone.

## Instalar

- **Android:** abre el enlace de Releases en el celular, descarga `Beside.apk` y ábrelo. Si lo pide, permite instalar apps de esa fuente.
- **iPhone (gratis):**
  1. Descarga `Beside.ipa` en el PC.
  2. Instálala con [Sideloadly](https://sideloadly.io), usando tu Apple ID y el iPhone conectado por cable.
  3. En el iPhone, ve a **Ajustes → General → VPN y gestión de dispositivos** y confía en tu Apple ID.
  4. Con una cuenta gratis de Apple, la app hay que volver a firmarla cada 7 días. Sideloadly puede hacerlo solo por Wi‑Fi.

  Con una cuenta de desarrollador de Apple (US$99 al año) se distribuye por TestFlight y dura 90 días.
- **Avisos:** instala **ntfy** (App Store o Play Store). Luego, en Beside, ve a **Perfil → Activar avisos en este celular**.

## Desarrollo

```bash
# Vista previa en el navegador con datos de ejemplo (sin cuenta)
flutter run -d chrome --dart-define=DEMO=true

# En un celular, con tu Supabase
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=SPOTIFY_CLIENT_ID=...
```

Mapa: © colaboradores de OpenStreetMap, teselas de Esri (World Dark Gray Canvas).
