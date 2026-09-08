# WispDating v0.9.1 – Release Notes

**Soft-Ping** – das einseitige Anschreiben für Transit Spark.

## Neu

- **Soft-Ping (einseitiges Anschreiben)**: Nach einer Begegnung im Radar
  kann die Person EINMAL diskret gegrüßt werden – mit vorgefertigten,
  freundlichen Sätzen plus optional einer kurzen eigenen Zeile (max.
  140 Zeichen, serverseitig gefiltert). Kein Freitext-Roman, kein Spam:
  genau 1 Versuch pro Begegnung, still verfallend nach 48 Stunden.
- **Empfänger entscheidet still**: dezente Push-Benachrichtigung
  (generischer Text – die eigene Zeile erscheint nur in der App), dann
  annehmen (= Funke über die Bestandspipeline) oder ausblenden. Der
  Absender erfährt NIEMALS eine Ablehnung – Schweigen = Ende.
- **Gruß-Sektion im Radar**: gesehene Geräte als anonyme Einträge
  („vor 2 Minuten"), jeder einmal grüßbar.
- **Server-Härtung (Migration 083)**: Presence-Tokens (nur das eigene,
  zufällige, TTL 45 min + Auto-Purge) machen den Gruß zustellbar;
  Whitelist für Sätze, Blockier-Prüfung in beide Richtungen, Rate-Limit
  (1 Ping / 30 min), Cron-Cleanup.

## Datenschutz (Transparenz-Erweiterung)

Der Privacy-Hinweis im Radar ist aktualisiert: Bei AKTIVEM Radar wird
das eigene zufällige Token (nur dieses) für 45 Minuten serverseitig
hinterlegt – sonst könnte ein Gruß die Person nicht erreichen. Beim
Deaktivieren wird es sofort entfernt. Keine Namen, kein Standort,
keine Fotos.

## Verteilung

| Datei | Zweck |
|---|---|
| WispDating-v0.9.1-play.apk | Google Play / direkte Verteilung |
| WispDating-v0.9.1-fdroid.apk | F-Droid (ohne Google) |
| WispDating-v0.9.1-play-arm64.apk | Play, nur arm64 |
| WispDating-v0.9.1-play-armv7.apk | Play, nur armv7 |
| WispDating-v0.9.1-fdroid-arm64.apk | F-Droid, nur arm64 |
| admin/WispDating-v0.9.1-play-ADMIN.apk | Admin-Build (NICHT verteilen) |
| admin/WispDating-v0.9.1-fdroid-ADMIN.apk | Admin-Build F-Droid (NICHT verteilen) |

## Vor dem Rollout

1. Migration **083** einspielen (Soft-Ping: Presence + Pings + RPCs +
   Push-Trigger + Cron).
2. Benötigt Migrationen 080–082 (aus v0.9.0).
