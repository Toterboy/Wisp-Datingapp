-- 054_unifiedpush.sql
--
-- Google-freier Push (F-Droid-Variante): Nutzer koennen einen
-- UnifiedPush-Endpunkt hinterlegen (z. B. eigenen ntfy-Server).
-- notify-user sendet dann dorthin statt via FCM. Die Spalte ist client-
-- schreibbar (eigene Zeile) - der Endpunkt enthält kein Geheimnis, nur einen
-- zufälligen Topic-Pfad des gewählten Distributors.

alter table public.profiles
  add column if not exists up_endpoint text;
