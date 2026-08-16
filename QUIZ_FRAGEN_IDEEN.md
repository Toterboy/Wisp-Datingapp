# QUIZ-FRAGEN: Ideen & Konzept für personalisierte Fragen

> Stand: 2026-08-14 · Reine Konzept-Dokumentation (keine Implementierung in diesem Durchlauf)

## Ziel

Das Quiz „Wie gut kenn ich mein Match" soll langfristig nicht nur generische
Fragen stellen (aktueller 100er-Pool, derzeit 5 Platzhalter in `quiz_questions`),
sondern **personalisierte Fragen**, die aus der individuellen Vorstellung der
jeweiligen Person (Text- und/oder Audio-Intro) generiert werden. Dadurch zeigt
das Quiz wirklich, ob man sich mit der Vorstellung der anderen Person
beschäftigt hat — statt Allgemeinwissen abzufragen.

## Konzept

1. **Quelle:** Die Vorstellungsfelder `profiles.intro_text` und
   `profiles.intro_audio_path` (Migration 033). Das Audio-Intro kann
   zusätzlich per Transkription (z. B. Whisper-API) in Text gewandelt werden,
   damit beide Formate in die Fragen-Generierung einfließen.
2. **Generierung:** Beim **Profil-Erstellen/-Update** (Trigger oder Edge
   Function) erzeugt ein LLM aus dem Intro 3-5 Fragen mit jeweils einer
   korrekten und 3 plausiblen falschen Antworten. Schema passt auf die
   bestehende `quiz_questions`-Tabelle (prompt, options jsonb, correct_index).
3. **Speicherung:** Neue Spalte `quiz_questions.owner_user_id uuid REFERENCES
   auth.users(id)` (nullable). `NULL` = generischer Pool, gesetzt =
   personalisierte Frage über diese Person.
4. **Auswahl im Quiz:** `start_quiz_attempt` zieht bevorzugt eine
   personalisierte Frage des Partners (owner = Partner), die für dieses Match
   noch unbenutzt ist; fällt keine an, wird auf den generischen Pool
   zurückgegriffen. Beide Partner bekommen weiterhin dieselbe Frage.
5. **Qualitätsschutz:** Automatische Prüfung, dass die korrekte Antwort
   tatsächlich aus dem Intro ableitbar ist (Selbstkonsistenz-Check des LLM);
   unbrauchbare Fragen werden verworfen. Optional manuelle Freigabe im
   Admin-Bereich.

## Umsetzungsansätze (Optionen)

| Ansatz | Beschreibung | Aufwand |
| --- | --- | --- |
| A: Edge Function bei Profil-Update | Client ruft nach dem Speichern `generate-quiz-questions` auf; Funktion liest Intro, ruft LLM (z. B. OpenRouter/Anthropic), schreibt Fragen mit owner_user_id. | Mittel; serverseitig sauber, LLM-Key bleibt im Secret |
| B: DB-Trigger + pg_net | Trigger feuert pg_net-Request an Edge Function. Nachteil: eingeschränkte Fehlerbehandlung/Idempotenz. | Niedrig, aber fragiler |
| C: Batch/Admin | Nächtlicher Cron generiert Fragen für neue/geänderte Profile. Keine Latenz beim Speichern. | Mittel; Fragen erscheinen verzögert |

Empfehlung: **Ansatz A** (explizit, testbar, LLM-Costs begrenzbar über
Rate-Limit + Cache: nur neu generieren, wenn sich das Intro geändert hat).

## Datenschutz

- Intros verlassen Supabase nur zur Generierung (LLM-Provider mit
  Datenverarbeitungsvertrag, EU-Region bevorzugt). Es werden keine
  Klarnamen/PII mitgesendet — nur der Intro-Text.
- Fragen werden mit dem Konto gelöscht (`ON DELETE CASCADE` über owner_user_id).
- Die korrekte Antwort bleibt weiterhin serverseitig (Client erhält nie
  `correct_index`).

## Offene Fragen / Entscheidungen

1. **LLM-Provider & Kostenbudget** (z. B. OpenRouter mit Pricelimit vs.
   Selbsthosting via Ollama).
2. **Audio-Transkription:** Sollen Audio-Intros transkribiert werden, oder
   generieren wir Fragen nur aus Text-Intros (Audio-Profile fallen dann auf
   den generischen Pool zurück)?
3. **Aktualisierungsstrategie:** Fragen bei jedem Profil-Update neu
   generieren oder nur bei Änderung des Intros (Diff via Hash)?
4. **Fragen-Anzahl pro Person:** 3, 5 oder mehr? Wiederverwendung nach
   Verbrauch (das Quiz kann beliebig oft versucht werden)?
5. **Mischverhältnis:** Soll das Quiz ausschließlich personalisierte Fragen
   stellen oder abwechselnd generische + personalisierte (Fairness, wenn der
   Partner kein Intro hat)?
6. **Qualitätssicherung:** Manuelle Freigabe im Admin-Screen nötig, oder
   reicht der automatische Selbstkonsistenz-Check?
7. **100er-Pool:** Wer erstellt die echten 100 generischen Fragen (Redaktion
   vs. LLM-generiert mit Review)?
8. **Sprache:** Mehrsprachigkeit (EN) später oder von Anfang an mitplanen?
