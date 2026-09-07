-- check_columns.sql - Diagnose: Welche v0.8-Spalten fehlen auf dem Server?
-- In Supabase Studio -> SQL Editor ausführen. TRUE = vorhanden, FALSE = Migration fehlt.

select
  -- Präferenzen (Suchradius!):
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='max_distance_km') as max_distance_km,
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='relationship_type') as relationship_type,
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='preferred_state') as preferred_state,
  -- Profilbilder:
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='photos') as photos,
  -- v0.8-Features:
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='music_liked') as music_liked,
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='ui_prefs') as ui_prefs,
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='paused') as paused,
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='profiles'
            and column_name='habits_dealbreaker') as habits_dealbreaker,
  -- Geräte:
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='auth_devices'
            and column_name='device_model') as device_model,
  -- View enthält Musik + Fotos?
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='public_profiles'
            and column_name='music_liked') as view_music,
  exists (select 1 from information_schema.columns
          where table_schema='public' and table_name='public_profiles'
            and column_name='photos') as view_photos;
