-- 062_realtime_signaling_authorization.sql
--
-- Audit M-10 / W-3: WebRTC-Signaling lief über einen öffentlichen
-- Broadcast-Channel mit deterministischem Topic-Namen
-- ('realtime:signaling:<uuidA>:<uuidB>') und client-gesetztem `from`-
-- Feld. JEDER authentifizierte Nutzer konnte das Topic abonnieren und
-- Offers/ICE-Kandidate mit gefälschtem Absender injizieren.
--
-- Fix: Realtime-Autorisierung (Private Channels). Der Client abonniert
-- den Kanal mit config.private = true (webrtc_service.dart); Realtime
-- prüft beim Join UND Broadcast gegen eine RLS-Policy auf
-- realtime.messages. Nur die beiden im Topic genannten Nutzer dürfen
-- den Kanal nutzen - Dritt-Injektion ist serverseitig unmöglich.
--
-- Die Policy ist strikt auf Signaling-Topics beschränkt und berührt
-- keine anderen Realtime-Nutzungen.

-- Voraussetzung für Realtime-Autorisierung ( Supabase Doku):
grant select on realtime.messages to authenticated;

drop policy if exists "signaling_channel_membership" on realtime.messages;
create policy "signaling_channel_membership"
  on realtime.messages
  for select to authenticated
  using (
    topic ~* '^realtime:signaling:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and (
      auth.uid()::text = split_part(topic, ':', 3)
      or auth.uid()::text = split_part(topic, ':', 4)
    )
  );

comment on policy "signaling_channel_membership" on realtime.messages is
'Signaling-Private-Channel (Audit M-10/W-3): nur die beiden im Topic '
'genannten Nutzer dürfen den WebRTC-Signaling-Kanal abonnieren/broadcasten. '
'Client: RealtimeChannelConfig(private: true).';
