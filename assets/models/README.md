# Modelle (On-Device-KI)

Dieser Ordner enthält lokale KI-Modelle für WispDating.

## image-safety-classifier-xs.onnx (NSFW-Bildmoderation, v0.8.0)

Die Datei `image-safety-classifier-xs.onnx` (OwenElliott/
image-safety-classifier-xs, Hugging Face) gehört HIER hinein und wird
in `pubspec.yaml` als Asset gebündelt.

- Eingang: 224x224 RGB, Float32, NCHW (Name in der Regel `input`)
- Ausgang: 3 Wahrscheinlichkeiten in der Reihenfolge `[NSFL, NSFW, SFW]`
- Nutzung: AUSSCHLIESSLICH lokale Vorprüfung nach manueller Bild-Meldung
  (Human-in-the-Loop) - niemals beim Senden/Empfangen (E2E-Schutz)
- Läuft über das Paket `onnxruntime` komplett auf dem Gerät

Fehlt die Datei, deaktiviert sich die lokale Prüfung automatisch
(`ImageSafetyService.isAvailable == false`) und der bisherige Flow
(serverseitiger Fallback-Scan) greift.
