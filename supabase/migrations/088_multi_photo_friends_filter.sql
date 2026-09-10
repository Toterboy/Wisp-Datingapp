-- 088_intro_audio_and_friends_filter.sql
--
-- v0.9.0-Feedback:
--
-- 1) Intro-Audio-Uploads scheiterten still: Der avatars-Bucket erlaubte
--    laut Migration 003 nur Bild-MIME-Typen ('image/jpeg', 'image/png',
--    'image/webp'). uploadIntroAudio() setzt keinen Content-Type
--    (Default text/plain) und die Datei ist audio/mp4 - mit aktivem
--    Whitelist-Regal wird der Upload verweigert. Folge: Die Vorstellung
--    mit Audio "verschwand" bei Aktualisierung/Neuinstallation (der
--    Pfad blieb leer/alt, das Audio fehlte). Fix: Bucket erlaubt jetzt
--    auch audio/mp4 (AAC/m4a) + audio/mpeg.
--
-- 2) "Ich suche" Reziprozitaet: Wer nach FREUNDEN sucht, findet nur
--    Personen, die ebenfalls "friends" eingestellt haben; umgekehrt
--    sehen Nicht-Freunde-Sucher keine Freunde-Sucher (die wollen keine
--    Dates).

-- ==========================================================================
-- 1) avatars-Bucket: Audio-MIME-Typen fuer die Audio-Vorstellung -----------
-- ==========================================================================
UPDATE storage.buckets
   SET allowed_mime_types = ARRAY[
         'image/jpeg', 'image/png', 'image/webp',
         'audio/mp4', 'audio/mpeg'
       ]
 WHERE id = 'avatars';

COMMENT ON COLUMN storage.buckets.file_size_limit IS
'088: avatars erlaubt jetzt auch Audio (intro.m4a, AAC).';

-- ==========================================================================
-- 2) get_find_match_candidates: "Ich suche"-Reziprozitaet ------------------
--    friends <-> friends, sonstige <-> sonstige. ---------------------------
-- ==========================================================================
create or replace function public.get_find_match_candidates(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  select coalesce(jsonb_agg(row_to_json(t) order by t.random_order), '[]'::jsonb)
    into v_result
    from (
      select p.*,
             (select public.profile_distance_km(p.user_id)) as distance_km,
             random() as random_order
        from public.public_profiles p
        join public.profiles me on me.user_id = v_user
        join public.profiles cand on cand.user_id = p.user_id
       where p.user_id <> v_user
         and (p.intro_text <> '' or p.intro_audio_path is not null)
         and not exists (
               select 1 from public.likes l
                where (l.user_id = v_user and l.liked_user_id = p.user_id)
                   or (l.user_id = p.user_id and l.liked_user_id = v_user))
         and not exists (
               select 1 from public.matches m
                where (m.user_one_id = v_user and m.user_two_id = p.user_id)
                   or (m.user_one_id = p.user_id and m.user_two_id = v_user))
         -- Viewer-Filter (bestehend).
         and (me.gender_preferences is null
              or me.gender_preferences = '{}'::text[]
              or p.gender = any(me.gender_preferences))
         and p.age between me.age_range_min and me.age_range_max
         -- Reziprozitaet: Praferenzen des Kandidaten (Audit M-2).
         and (cand.gender_preferences is null
              or cand.gender_preferences = '{}'::text[]
              or me.gender = any(cand.gender_preferences))
         and public.profile_age(me.birth_date)
             between cand.age_range_min and cand.age_range_max
         -- Konsum-Filter aus 047 (in 050 versehentlich verloren gegangen).
         and (me.smoking is null or me.smoking = ''
              or coalesce(public._habitude_rank(p.smoking), 0)
                 <= public._habitude_rank(me.smoking))
         and (me.alcohol is null or me.alcohol = ''
              or coalesce(public._habitude_rank(p.alcohol), 0)
                 <= public._habitude_rank(me.alcohol))
         and (me.drugs is null or me.drugs = ''
              or coalesce(public._habitude_rank(p.drugs), 0)
                 <= public._habitude_rank(me.drugs))
         -- NEU (088): "Ich suche"-Reziprozitaet. Freunde-Sucher sehen nur
         -- Freunde-Sucher (beide Seiten wollen keine Dates); alle anderen
         -- Beziehungsarten sehen einander, aber nie Freunde-Sucher.
         and ((coalesce(me.relationship_type, 'other') = 'friends')
              = (coalesce(cand.relationship_type, 'other') = 'friends'))
       order by random()
       limit least(p_limit, 50)
    ) t;
  return v_result;
end;
$$;

revoke all on function public.get_find_match_candidates(int) from public;
grant execute on function public.get_find_match_candidates(int) to authenticated;
