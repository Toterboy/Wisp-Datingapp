# ADR-0004: 2FA ausschließlich per TOTP (keine SMS)

- Status: angenommen
- Datum: 2026-08 (Build-Phase)

## Kontext

Zweitfaktor für den Account-Schutz. Optionen: SMS-Code, E-Mail-Code,
Authenticator-App (TOTP), Passkeys/WebAuthn.

## Entscheidung

TOTP (Google Authenticator, Aegis, 2FAS, Apple Codes) als einziger
zweiter Faktor; ergänzend Passkeys als phishing-resistenter Login ohne
Passwort. SMS und E-Mail werden bewusst NICHT angeboten.

## Konsequenzen

+ SMS-MFA ist angreifbar (SIM-Swapping) und kostet pro Nachricht – beides
  unvereinbar mit dem Sicherheitsanspruch und dem Kostenmodell.
+ TOTP ist offline prüfbar durch den Nutzer, standardisiert und anbieterfrei.
− Nutzer brauchen eine Authenticator-App (heute weit verbreitet); Verlust des
  Geräts erfordert Support-Weg über die Einladungs-/Support-Kommunikation.
