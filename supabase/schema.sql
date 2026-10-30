-- =====================================================================
-- Beside · base de datos en Supabase (plan gratis)
-- Pega todo este archivo en Supabase → SQL Editor → Run. Se puede correr
-- otra vez sin romper nada.
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------

-- Perfil público de cada persona (nombre, foto y color en el mapa)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  avatar_url text,
  color text not null default '#F2789A',
  created_at timestamptz not null default now()
);

-- Ajustes privados: solo los ve su dueño (y el servidor para enviar avisos)
create table if not exists public.private_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  ntfy_topic text,
  notify_enabled boolean not null default true
);

-- Un círculo agrupa a las personas que se ven entre sí (por ejemplo: Familia)
create table if not exists public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.circle_members (
  circle_id uuid not null references public.circles (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

-- Lugares marcados del círculo (casa, trabajo, gym...)
create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles (id) on delete cascade,
  name text not null,
  icon text not null default 'pin',
  lat double precision not null,
  lng double precision not null,
  radius_m integer not null default 100 check (radius_m between 30 and 2000),
  notify_enter boolean not null default true,
  notify_exit boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

-- Última posición de cada persona: lo que se ve en el mapa en vivo
create table if not exists public.live_locations (
  user_id uuid primary key references auth.users (id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  accuracy real,
  speed real,
  heading real,
  battery smallint,
  charging boolean,
  place_id uuid references public.places (id) on delete set null,
  place_since timestamptz,
  updated_at timestamptz not null default now(),
  -- Lo que suena en su Spotify
  track_name text,
  track_artist text,
  track_image text,
  track_url text,
  track_progress_ms integer,
  track_duration_ms integer,
  track_playing boolean,
  track_at timestamptz
);

-- Recorridos: se guardan 30 días y luego se borran solos
create table if not exists public.location_points (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  accuracy real,
  speed real,
  recorded_at timestamptz not null default now()
);
create index if not exists location_points_user_time on public.location_points (user_id, recorded_at desc);

-- En qué lugares está cada persona ahora mismo
create table if not exists public.presence (
  user_id uuid not null references auth.users (id) on delete cascade,
  place_id uuid not null references public.places (id) on delete cascade,
  since timestamptz not null default now(),
  primary key (user_id, place_id)
);

-- Llegadas y salidas (también se borran a los 30 días)
create table if not exists public.place_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  place_id uuid references public.places (id) on delete cascade,
  place_name text not null,
  kind text not null check (kind in ('enter', 'exit')),
  at timestamptz not null default now()
);
create index if not exists place_events_user_time on public.place_events (user_id, at desc);

-- ---------------------------------------------------------------------
-- Funciones de ayuda
-- ---------------------------------------------------------------------

create or replace function public.is_member(circle uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from circle_members where circle_id = circle and user_id = auth.uid());
$$;

-- ¿Comparto algún círculo con esta persona?
create or replace function public.shares_circle(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select other = auth.uid() or exists (
    select 1 from circle_members a
    join circle_members b on a.circle_id = b.circle_id
    where a.user_id = auth.uid() and b.user_id = other
  );
$$;

-- Distancia en metros entre dos coordenadas (fórmula del haversine)
create or replace function public.distance_m(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- Perfil automático al registrarse
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name) values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''))
  on conflict (id) do nothing;
  insert into private_settings (user_id, ntfy_topic)
  values (new.id, 'beside-' || replace(gen_random_uuid()::text, '-', ''))
  on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Círculos: crear, unirse con el código y salir
-- ---------------------------------------------------------------------

create or replace function public.new_circle_code()
returns text language plpgsql as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  candidate text;
begin
  loop
    candidate := 'BSD-';
    for i in 1..4 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from circles where code = candidate);
  end loop;
  return candidate;
end $$;

create or replace function public.create_circle(circle_name text)
returns public.circles language plpgsql security definer set search_path = public as $$
declare
  c circles;
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  insert into circles (name, code, created_by)
  values (coalesce(nullif(trim(circle_name), ''), 'Mi círculo'), new_circle_code(), auth.uid())
  returning * into c;
  insert into circle_members (circle_id, user_id) values (c.id, auth.uid());
  return c;
end $$;

create or replace function public.join_circle(invite_code text)
returns public.circles language plpgsql security definer set search_path = public as $$
declare
  c circles;
  clean text := upper(regexp_replace(coalesce(invite_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  -- Acepta "BSD-4K7Q", "bsd4k7q" o solo "4K7Q"
  if length(clean) = 4 then clean := 'BSD' || clean; end if;
  select * into c from circles where replace(code, '-', '') = clean;
  if not found then raise exception 'No encontramos ese código. Revisa que esté bien escrito.'; end if;
  insert into circle_members (circle_id, user_id) values (c.id, auth.uid()) on conflict do nothing;
  return c;
end $$;

create or replace function public.leave_circle(circle uuid)
returns void language sql security definer set search_path = public as $$
  delete from circle_members where circle_id = circle and user_id = auth.uid();
$$;

grant execute on function public.create_circle(text), public.join_circle(text), public.leave_circle(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Detección de llegadas y salidas en el servidor
-- Entra: dentro del radio y con una lectura lo bastante precisa.
-- Sale: fuera del radio más un margen, para que el GPS no haga saltar avisos falsos.
-- ---------------------------------------------------------------------

create or replace function public.evaluate_places()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p record;
  d double precision;
  acc double precision := coalesce(new.accuracy, 0);
  inside boolean;
  best_place uuid;
  best_distance double precision := 1e12;
begin
  if tg_op = 'UPDATE' and new.lat = old.lat and new.lng = old.lng then
    return new;
  end if;

  for p in
    select distinct pl.* from places pl
    join circle_members cm on cm.circle_id = pl.circle_id
    where cm.user_id = new.user_id
  loop
    d := distance_m(new.lat, new.lng, p.lat, p.lng);
    inside := exists (select 1 from presence where user_id = new.user_id and place_id = p.id);

    if not inside and d <= p.radius_m and acc <= greatest(p.radius_m, 60) then
      insert into presence (user_id, place_id) values (new.user_id, p.id) on conflict do nothing;
      insert into place_events (user_id, place_id, place_name, kind) values (new.user_id, p.id, p.name, 'enter');
      inside := true;
    elsif inside and d > p.radius_m + greatest(25, least(acc, 150)) then
      delete from presence where user_id = new.user_id and place_id = p.id;
      insert into place_events (user_id, place_id, place_name, kind) values (new.user_id, p.id, p.name, 'exit');
      inside := false;
    end if;

    if inside and d < best_distance then
      best_distance := d;
      best_place := p.id;
    end if;
  end loop;

  if best_place is distinct from (case when tg_op = 'UPDATE' then old.place_id end) then
    new.place_id := best_place;
    new.place_since := case when best_place is null then null else now() end;
  end if;
  return new;
end $$;

drop trigger if exists live_locations_places on public.live_locations;
create trigger live_locations_places before insert or update on public.live_locations
  for each row execute function public.evaluate_places();

-- Avisos: cada llegada o salida se envía a las otras personas del círculo
-- por ntfy (app gratis para iPhone y Android).
create or replace function public.notify_place_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  pl places;
  mover text;
  target record;
begin
  select * into pl from places where id = new.place_id;
  if not found then return new; end if;
  if (new.kind = 'enter' and not pl.notify_enter) or (new.kind = 'exit' and not pl.notify_exit) then
    return new;
  end if;
  select coalesce(nullif(name, ''), 'Alguien') into mover from profiles where id = new.user_id;

  for target in
    select ps.ntfy_topic from circle_members cm
    join private_settings ps on ps.user_id = cm.user_id
    where cm.circle_id = pl.circle_id and cm.user_id <> new.user_id
      and ps.notify_enabled and ps.ntfy_topic is not null
  loop
    perform net.http_post(
      url := 'https://ntfy.sh',
      body := jsonb_build_object(
        'topic', target.ntfy_topic,
        'title', case when new.kind = 'enter' then mover || ' llegó a ' || new.place_name else mover || ' salió de ' || new.place_name end,
        'message', to_char(new.at at time zone 'America/Bogota', 'HH12:MI a. m.'),
        'tags', jsonb_build_array(case when new.kind = 'enter' then 'round_pushpin' else 'wave' end),
        'priority', 4,
        'click', 'beside://'
      ),
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  end loop;
  return new;
end $$;

drop trigger if exists place_events_notify on public.place_events;
create trigger place_events_notify after insert on public.place_events
  for each row execute function public.notify_place_event();

-- ---------------------------------------------------------------------
-- Rastreo en segundo plano con llave de dispositivo
-- El servicio que comparte la ubicación no depende de la sesión (que vence):
-- al iniciar sesión, el teléfono registra una llave propia y la usa para
-- publicar su posición, batería y canción aunque la app esté cerrada.
-- ---------------------------------------------------------------------

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.devices (
  key_hash text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text,
  created_at timestamptz not null default now(),
  last_seen timestamptz
);
alter table public.devices enable row level security;

create or replace function public.register_device(device_platform text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  raw_key text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  insert into devices (key_hash, user_id, platform)
  values (encode(extensions.digest(raw_key, 'sha256'), 'hex'), auth.uid(), device_platform);
  return raw_key;
end $$;

create or replace function public.device_user(device_key text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid;
begin
  update devices set last_seen = now()
  where key_hash = encode(extensions.digest(coalesce(device_key, ''), 'sha256'), 'hex')
  returning user_id into uid;
  if uid is null then raise exception 'Dispositivo no registrado'; end if;
  return uid;
end $$;

create or replace function public.push_location(
  device_key text, p_lat double precision, p_lng double precision, p_accuracy real, p_speed real, p_heading real,
  p_battery integer, p_charging boolean, p_save_point boolean, p_recorded_at timestamptz default now()
) returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := device_user(device_key);
  at_time timestamptz := least(coalesce(p_recorded_at, now()), now());
begin
  insert into live_locations (user_id, lat, lng, accuracy, speed, heading, battery, charging, updated_at)
  values (uid, p_lat, p_lng, p_accuracy, p_speed, p_heading, p_battery, p_charging, at_time)
  on conflict (user_id) do update set
    lat = excluded.lat, lng = excluded.lng, accuracy = excluded.accuracy, speed = excluded.speed,
    heading = excluded.heading, battery = coalesce(excluded.battery, live_locations.battery),
    charging = coalesce(excluded.charging, live_locations.charging), updated_at = excluded.updated_at;
  if p_save_point then
    insert into location_points (user_id, lat, lng, accuracy, speed, recorded_at)
    values (uid, p_lat, p_lng, p_accuracy, p_speed, at_time);
  end if;
end $$;

-- Puntos que se guardaron sin internet y se envían después
create or replace function public.push_points(device_key text, points jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := device_user(device_key);
begin
  insert into location_points (user_id, lat, lng, accuracy, speed, recorded_at)
  select uid, (p ->> 'lat')::double precision, (p ->> 'lng')::double precision, (p ->> 'accuracy')::real,
         (p ->> 'speed')::real, least((p ->> 'at')::timestamptz, now())
  from jsonb_array_elements(points) p
  where (p ->> 'at')::timestamptz > now() - interval '30 days';
end $$;

-- Señal de vida sin moverse: actualiza batería y hora sin tocar la posición
create or replace function public.push_heartbeat(device_key text, p_battery integer, p_charging boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := device_user(device_key);
begin
  update live_locations set battery = p_battery, charging = p_charging, updated_at = now() where user_id = uid;
end $$;

create or replace function public.push_track(
  device_key text, p_name text, p_artist text, p_image text, p_url text, p_progress integer, p_duration integer, p_playing boolean
) returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := device_user(device_key);
begin
  update live_locations set track_name = p_name, track_artist = p_artist, track_image = p_image, track_url = p_url,
    track_progress_ms = p_progress, track_duration_ms = p_duration, track_playing = p_playing, track_at = now()
  where user_id = uid;
end $$;

revoke all on function public.device_user(text) from public, anon, authenticated;
grant execute on function public.register_device(text) to authenticated;
grant execute on function public.push_location(text, double precision, double precision, real, real, real, integer, boolean, boolean, timestamptz) to anon, authenticated;
grant execute on function public.push_points(text, jsonb), public.push_heartbeat(text, integer, boolean),
  public.push_track(text, text, text, text, text, integer, integer, boolean) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Seguridad: cada quien solo ve a las personas de sus círculos
-- ---------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.private_settings enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.places enable row level security;
alter table public.live_locations enable row level security;
alter table public.location_points enable row level security;
alter table public.presence enable row level security;
alter table public.place_events enable row level security;

drop policy if exists "ver perfiles del círculo" on public.profiles;
create policy "ver perfiles del círculo" on public.profiles for select using (shares_circle(id));
drop policy if exists "editar mi perfil" on public.profiles;
create policy "editar mi perfil" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "crear mi perfil" on public.profiles;
create policy "crear mi perfil" on public.profiles for insert with check (id = auth.uid());

drop policy if exists "mis ajustes" on public.private_settings;
create policy "mis ajustes" on public.private_settings for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "ver mis círculos" on public.circles;
create policy "ver mis círculos" on public.circles for select using (is_member(id));
drop policy if exists "renombrar mis círculos" on public.circles;
create policy "renombrar mis círculos" on public.circles for update using (is_member(id));

drop policy if exists "ver miembros" on public.circle_members;
create policy "ver miembros" on public.circle_members for select using (is_member(circle_id));

drop policy if exists "lugares del círculo" on public.places;
create policy "lugares del círculo" on public.places for all using (is_member(circle_id)) with check (is_member(circle_id));

drop policy if exists "ver ubicaciones" on public.live_locations;
create policy "ver ubicaciones" on public.live_locations for select using (shares_circle(user_id));
drop policy if exists "publicar mi ubicación" on public.live_locations;
create policy "publicar mi ubicación" on public.live_locations for insert with check (user_id = auth.uid());
drop policy if exists "actualizar mi ubicación" on public.live_locations;
create policy "actualizar mi ubicación" on public.live_locations for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "ver recorridos" on public.location_points;
create policy "ver recorridos" on public.location_points for select using (shares_circle(user_id));
drop policy if exists "guardar mi recorrido" on public.location_points;
create policy "guardar mi recorrido" on public.location_points for insert with check (user_id = auth.uid());

drop policy if exists "ver presencia" on public.presence;
create policy "ver presencia" on public.presence for select using (shares_circle(user_id));

drop policy if exists "ver llegadas" on public.place_events;
create policy "ver llegadas" on public.place_events for select using (shares_circle(user_id));

-- Tiempo real para el mapa, los lugares y los avisos dentro de la app
do $$
declare t text;
begin
  foreach t in array array['live_locations', 'place_events', 'places', 'profiles', 'circle_members'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Fotos de perfil
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "subir mi foto" on storage.objects;
create policy "subir mi foto" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "cambiar mi foto" on storage.objects;
create policy "cambiar mi foto" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "borrar mi foto" on storage.objects;
create policy "borrar mi foto" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- Limpieza diaria (3:15 a. m. en Colombia): borra recorridos y llegadas
-- de más de 30 días, para no pasarse nunca del plan gratis.
-- ---------------------------------------------------------------------

select cron.unschedule(jobid) from cron.job where jobname = 'beside-limpieza';
select cron.schedule('beside-limpieza', '15 8 * * *', $$
  delete from public.location_points where recorded_at < now() - interval '30 days';
  delete from public.place_events where at < now() - interval '30 days';
$$);

-- ---------------------------------------------------------------------
-- Avisos de batería (también en supabase/alertas_bateria.sql)
-- ---------------------------------------------------------------------
alter table public.live_locations add column if not exists battery_alert smallint;      -- último nivel avisado (20, 10, 5)
alter table public.live_locations add column if not exists charge_alert_at timestamptz;  -- último aviso de "lo puso a cargar"
alter table public.live_locations add column if not exists full_alerted boolean not null default false;
alter table public.live_locations add column if not exists offline_alerted boolean not null default false;

-- Envía un aviso a todas las personas que comparten círculo con [who] (menos a ella misma)
create or replace function public.notify_circle(who uuid, title text, message text, tag text, prio integer default 3)
returns void language plpgsql security definer set search_path = public as $$
declare
  target record;
begin
  for target in
    select distinct ps.ntfy_topic
    from circle_members mine
    join circle_members other on other.circle_id = mine.circle_id and other.user_id <> who
    join private_settings ps on ps.user_id = other.user_id
    where mine.user_id = who and ps.notify_enabled and ps.ntfy_topic is not null
  loop
    perform net.http_post(
      url := 'https://ntfy.sh',
      body := jsonb_build_object(
        'topic', target.ntfy_topic,
        'title', title,
        'message', message,
        'tags', jsonb_build_array(tag),
        'priority', prio,
        'click', 'beside://'
      ),
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  end loop;
end $$;

revoke all on function public.notify_circle(uuid, text, text, text, integer) from public, anon, authenticated;

-- Revisa cada actualización de batería
create or replace function public.battery_alerts()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text;
  lvl smallint;
begin
  -- Volvió a enviar señal: se puede volver a avisar si se apaga otra vez
  if new.updated_at > old.updated_at then
    new.offline_alerted := false;
  end if;

  if new.battery is null then
    return new;
  end if;
  select coalesce(nullif(name, ''), 'Alguien') into who from profiles where id = new.user_id;

  -- Lo puso a cargar (máximo un aviso cada 15 minutos, por si el cable hace falso contacto)
  if coalesce(new.charging, false) and not coalesce(old.charging, false)
     and (new.charge_alert_at is null or new.charge_alert_at < now() - interval '15 minutes') then
    new.charge_alert_at := now();
    perform notify_circle(new.user_id, who || ' puso a cargar el celular', 'Tenía ' || new.battery || ' % de batería', 'electric_plug', 3);
  end if;

  -- Cargando o con buena batería: se reinician los avisos de batería baja
  if coalesce(new.charging, false) or new.battery >= 30 then
    new.battery_alert := null;
  end if;

  -- Terminó de cargar
  if coalesce(new.charging, false) and new.battery >= 100 and not new.full_alerted then
    new.full_alerted := true;
    perform notify_circle(new.user_id, who || ' ya tiene el celular cargado', 'Batería al 100 %', 'battery', 2);
  elsif new.battery < 95 then
    new.full_alerted := false;
  end if;

  -- Se está descargando: avisa al cruzar 20 %, 10 % y 5 %
  if not coalesce(new.charging, false) then
    lvl := case when new.battery <= 5 then 5 when new.battery <= 10 then 10 when new.battery <= 20 then 20 else null end;
    if lvl is not null and (new.battery_alert is null or lvl < new.battery_alert) then
      new.battery_alert := lvl;
      perform notify_circle(
        new.user_id,
        case when lvl = 5 then 'A ' || who || ' se le va a apagar el celular'
             else 'A ' || who || ' se le está descargando el celular' end,
        'Le queda ' || new.battery || ' % de batería',
        'warning',
        case when lvl = 5 then 5 else 4 end
      );
    end if;
  end if;

  return new;
end $$;

drop trigger if exists live_locations_battery on public.live_locations;
create trigger live_locations_battery before update on public.live_locations
  for each row execute function public.battery_alerts();

-- Cada 5 minutos: ¿alguien con poca batería dejó de enviar señal?
create or replace function public.check_offline()
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
  who text;
begin
  for r in
    select * from live_locations
    where not offline_alerted
      and updated_at < now() - interval '20 minutes'
      and updated_at > now() - interval '6 hours'
      and battery is not null and battery <= 15
      and not coalesce(charging, false)
  loop
    select coalesce(nullif(name, ''), 'Alguien') into who from profiles where id = r.user_id;
    perform notify_circle(
      r.user_id,
      'Puede que a ' || who || ' se le haya apagado el celular',
      'No envía su ubicación desde las ' || to_char(r.updated_at at time zone 'America/Bogota', 'HH12:MI a. m.') || ' y tenía ' || r.battery || ' % de batería',
      'zzz',
      4
    );
    update live_locations set offline_alerted = true where user_id = r.user_id;
  end loop;
end $$;

revoke all on function public.check_offline() from public, anon, authenticated;

select cron.unschedule('beside-sin-senal') where exists (select 1 from cron.job where jobname = 'beside-sin-senal');
select cron.schedule('beside-sin-senal', '*/5 * * * *', 'select public.check_offline()');
