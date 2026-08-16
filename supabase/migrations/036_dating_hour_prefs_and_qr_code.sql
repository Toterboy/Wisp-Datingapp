-- 036_dating_hour_prefs_and_qr_code.sql
-- 1) Dating-Hour-Präferenzen speichern OHNE beizutreten.
--    Vorher: Der Client nutzte join_dating_hour auch nur zum Speichern von
--    Präferenzen -> Speichern trat automatisch bei. Jetzt: Speichern ändert
--    NUR die Präferenzen; die Teilnahme (left_at) bleibt unverändert.
--    Neue Zeilen starten als NICHT teilnehmend (left_at = now()).

create or replace function public.save_dating_hour_preferences(
  p_event_id uuid,
  p_preferences jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  insert into public.dating_hour_participant (event_id, user_id, preferences, left_at)
  values (p_event_id, v_user_id, p_preferences, now())
  on conflict (event_id, user_id)
  do update set preferences = excluded.preferences;
end;
$$;

revoke all on function public.save_dating_hour_preferences(uuid, jsonb) from public;
grant execute on function public.save_dating_hour_preferences(uuid, jsonb) to authenticated;

-- 2) Nutzer anhand seines teilbaren Kurz-Codes finden (erste 8 Zeichen der
--    User-ID ohne Bindestriche, Großbuchstaben). Erlaubt die manuelle
--    Code-Eingabe beim QR-Scannen. Exakte 8-Zeichen-Übereinstimmung
--    (kein Wildcard-Prefix), um Raten/Enumeration zu erschweren.

create or replace function public.find_user_by_code(p_code text)
returns table (user_id uuid)
language sql
security definer
set search_path = ''
as $$
  select p.user_id
  from public.profiles p
  where length(trim(p_code)) = 8
    and upper(left(regexp_replace(p.user_id::text, '-', '', 'g'), 8))
        = upper(trim(p_code))
  limit 1;
$$;

revoke all on function public.find_user_by_code(text) from public;
grant execute on function public.find_user_by_code(text) to authenticated;
