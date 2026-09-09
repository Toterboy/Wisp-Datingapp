-- repair_transit_prekeys.sql - Diagnose fuer den Zufallschat-500
-- ("Datenbankfehler beim Abruf" aus der prekeys-Edge-Function).
-- Nach Migrationen kann der PostgREST-Schema-Cache veraltet sein.
-- 1) Existiert die prekeys-Tabelle? 2) Cache neu laden. 3) Zaehler.

select count(*) as prekeys_tabellen_zeilen from public.prekeys;

NOTIFY pgrst, 'reload schema';

select count(*) as prekeys_aktiv from public.prekeys;
select count(*) as transit_signale from public.transit_signals;
select proname from pg_proc
 where proname in ('match_proximity_spark', 'like_user', 'join_random_chat');
