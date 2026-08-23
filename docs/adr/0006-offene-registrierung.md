# ADR-0006: Einladungscodes entfernt – offene Registrierung

- Status: angenommen (ersetzt frühere Beta-Zugangsplanung)
- Datum: 2026-08-23

## Kontext

Während der geschlossenen Build-Phase war eine Einladungscode-Pflicht
geplant (Bot-/Massen-Schutz). Das behinderte jedoch den Beta-Start und
widerspricht dem Ziel einer offen zugänglichen, gemeinwohlorientierten App.

## Entscheidung

Das Einladungscode-System wurde vollständig aus dem Client entfernt
(Feld, Validierungskette, Modell/Service, Route). Die Registrierung steht
allen offen. Schutz gegen Massen-Registrierung leisten stattdessen:
optionales CAPTCHA (Cloudflare Turnstile, serverseitig validiert),
serverseitige Rate-Limits sowie die bestehende E-Mail-Sperr-Infrastruktur.

## Konsequenzen

+ Niedrigere Einstiegshürde; weniger Wartungscode (Client-seitig vollständig
  entfernt); keine Schlüsselverteilung durch den Betreiber.
− Theoretisch einfacherer Missbrauch durch Wegfall der Zugangsschranke;
  gemildert durch CAPTCHA + Rate-Limits + Ban-System mit Entsperrungsantrag.
− Serverseitig verbliebene Reste (`invite_codes`-Tabelle,
  `validate_invite_code`-RPC) sind funktional tot und werden bei Gelegenheit
  in einer Aufräum-Migration entfernt.
