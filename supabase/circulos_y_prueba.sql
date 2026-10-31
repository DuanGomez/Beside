-- =====================================================================
-- Beside · Manejo de círculos, aviso de prueba y ubicación aproximada
-- Pega TODO este archivo en Supabase → SQL Editor y dale Run (una vez).
-- Se puede volver a ejecutar sin problema.
-- =====================================================================

-- Sacar a alguien de un círculo (solo quien lo creó)
create or replace function public.remove_member(circle uuid, member uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from circles where id = circle and created_by = auth.uid()) then
    raise exception 'Solo quien creó el círculo puede sacar a alguien';
  end if;
  if member = auth.uid() then
    raise exception 'No te puedes sacar a ti mismo; usa «Eliminar círculo»';
  end if;
  delete from circle_members where circle_id = circle and user_id = member;
end $$;

-- Eliminar un círculo con sus lugares (solo quien lo creó)
create or replace function public.delete_circle(circle uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from circles where id = circle and created_by = auth.uid()) then
    raise exception 'Solo quien creó el círculo puede eliminarlo';
  end if;
  delete from circles where id = circle;
end $$;

grant execute on function public.remove_member(uuid, uuid), public.delete_circle(uuid) to authenticated;

-- Aviso de prueba a mi propio ntfy (para revisar que lleguen)
create or replace function public.send_test_notification()
returns text language plpgsql security definer set search_path = public as $$
declare
  topic text;
begin
  select ntfy_topic into topic from private_settings where user_id = auth.uid();
  if topic is null then
    raise exception 'No tienes canal de avisos';
  end if;
  perform net.http_post(
    url := 'https://ntfy.sh',
    body := jsonb_build_object(
      'topic', topic,
      'title', 'Beside: aviso de prueba',
      'message', 'Si ves esto, los avisos de llegadas y batería te van a llegar.',
      'tags', jsonb_build_array('tada'),
      'priority', 4,
      'click', 'beside://'
    ),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
  return topic;
end $$;

grant execute on function public.send_test_notification() to authenticated;

-- Llegadas y salidas: una ubicación aproximada (sin «Ubicación precisa»,
-- con error de más de 300 m) nunca marca una salida falsa.
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
    elsif inside and acc <= 300 and d > p.radius_m + greatest(25, least(acc, 150)) then
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

-- ---------------------------------------------------------------------
-- DIAGNÓSTICO (opcional): para ver cómo está cada persona, ejecuta solo
-- esta consulta (selecciónala y dale Run):
--
-- select p.name,
--        l.updated_at at time zone 'America/Bogota' as ultima_ubicacion,
--        round(l.accuracy) as precision_m, l.battery, l.charging,
--        (select count(*) from devices d where d.user_id = p.id) as celulares,
--        (select max(last_seen) at time zone 'America/Bogota' from devices d where d.user_id = p.id) as ultimo_contacto,
--        ps.notify_enabled as avisos
-- from profiles p
-- left join live_locations l on l.user_id = p.id
-- left join private_settings ps on ps.user_id = p.id
-- order by p.name;
-- ---------------------------------------------------------------------
