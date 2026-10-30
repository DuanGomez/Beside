-- =====================================================================
-- Beside · Avisos de batería
-- Pega TODO este archivo en Supabase → SQL Editor y dale Run (una vez).
-- Se puede volver a ejecutar sin problema.
--
-- Avisa por ntfy a las personas del círculo cuando alguien:
--   • baja a 20 %, 10 % o 5 % de batería (una vez por nivel)
--   • pone a cargar el celular
--   • termina de cargar (100 %)
--   • deja de enviar su ubicación con poca batería (posible celular apagado)
-- =====================================================================

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
