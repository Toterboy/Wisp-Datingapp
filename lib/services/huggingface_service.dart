import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:wisp/utils/constants.dart';

/// Service für die Hugging Face Inference API.
///
/// Nutzt das Modell `Falconsai/nsfw_image_detection` zur Klassifikation von
/// Bildern in Kategorien: drawings, hentai, neutral, porn, sexy.
///
/// API: POST https://api-inference.huggingface.co/models/Falconsai/nsfw_image_detection
/// Token: --dart-define=HF_API_TOKEN=hf_xxx...
class HuggingFaceService {
  HuggingFaceService._();

  /// Basis-URL für das NSFW-Modell. Konfigurierbar via --dart-define,
  /// um z. B. einen EU-basierten Inference-Endpunkt zu nutzen.
  static final String _baseUrl = AppConstants.hfInferenceUrl;

  /// Kategorien, die als NSFW gelten und zur Ablehnung führen.
  static const _nsfwCategories = {'porn', 'hentai'};

  /// Kategorien, die als "grau" gelten und manuelle Prüfung empfehlen.
  static const _grayCategories = {'sexy', 'drawings'};

  /// Schwellenwert: Score > threshold → Kategorie gilt als erkannt.
  static const double _nsfwThreshold = 0.5;
  static const double _grayThreshold = 0.3;

  /// Timeout für die HTTP-Verbindung.
  static const Duration timeout = Duration(seconds: 5);

  /// Ergebnis der NSFW-Prüfung.
  /// [isSafe]: true = Bild kann durchgelassen werden.
  /// [isNsfw]: true = explizite NSFW-Kategorie mit hohem Score erkannt.
  /// [categories]: Rohdaten der API-Antwort.
  /// [label]: Label mit dem höchsten Score.
  /// [needsReview]: true = API nicht erreichbar → manuelle Prüfung nötig.
  static Future<({bool isSafe, bool isNsfw, bool needsReview, Map<String, dynamic> categories, String label})> checkImage(Uint8List imageBytes) async {
    final token = AppConstants.hfApiToken;
    if (token.isEmpty) {
      if (kDebugMode) debugPrint('[HF] Kein API-Token konfiguriert — Moderation deaktiviert.');
      return (isSafe: true, isNsfw: false, needsReview: true, categories: <String, dynamic>{}, label: 'no_token');
    }

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/octet-stream',
            },
            body: imageBytes,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as List<dynamic>;
        final categories = <String, double>{};
        for (final entry in result) {
          final label = entry['label'] as String;
          final score = (entry['score'] as num).toDouble();
          categories[label] = score;
        }

        final topLabel = categories.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;

        final isNsfw = _nsfwCategories.any(
          (cat) => (categories[cat] ?? 0) > _nsfwThreshold,
        );
        final isGray = _grayCategories.any(
          (cat) => (categories[cat] ?? 0) > _grayThreshold,
        );

        return (
          isSafe: !isNsfw,
          isNsfw: isNsfw,
          needsReview: isGray && !isNsfw,
          categories: Map<String, dynamic>.from(categories),
          label: topLabel,
        );
      }

      // Modell lädt (erster Request nach Inaktivität) → pending.
      if (response.statusCode == 503) {
        if (kDebugMode) debugPrint('[HF] Modell lädt (503) — pending review.');
        return (isSafe: false, isNsfw: false, needsReview: true, categories: <String, dynamic>{}, label: 'model_loading');
      }

      // Anderer Fehler.
      if (kDebugMode) debugPrint('[HF] API-Fehler ${response.statusCode}: ${response.body}');
      return (isSafe: false, isNsfw: false, needsReview: true, categories: <String, dynamic>{}, label: 'api_error');
    } catch (e) {
      if (kDebugMode) debugPrint('[HF] Request fehlgeschlagen: $e');
      return (isSafe: false, isNsfw: false, needsReview: true, categories: <String, dynamic>{}, label: 'timeout');
    }
  }
}
