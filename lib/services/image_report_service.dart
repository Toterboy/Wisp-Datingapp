import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/message.dart';
import 'package:wisp/models/report_models.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/services/report_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';

/// Ergebnis der Bild-Meldung mit KI-Vorprüfung.
class ImageReportOutcome {
  const ImageReportOutcome({
    required this.aiAvailable,
    required this.aiAgrees,
    required this.score,
    required this.operatorNotified,
  });

  /// War der KI-Scan verfügbar (Token konfiguriert, kein Fehler)?
  final bool aiAvailable;

  /// Sieht die KI das Bild als unangemessen (NSFW)?
  final bool aiAgrees;

  /// NSFW-Score 0..1 (nur sinnvoll, wenn [aiAvailable]).
  final double score;

  /// Hat die Betreiber-Mail das Team erreicht?
  final bool operatorNotified;
}

/// Bild-Meldung mit automatischer KI-Vorprüfung (Chat-Bilder).
///
/// Grundsatz: Chat-Bilder werden NIE automatisch beim Senden gescannt
/// (E2E). Nur wenn der Empfänger ein Bild meldet, wird exakt dieses eine
/// Bild an die Edge Function `report-image` übermittelt, dort von einem
/// NSFW-Klassifikator geprüft und das Ergebnis (Bild, Report, KI-Score)
/// per E-Mail an das Moderations-Team gesendet.
///
/// Der Meldende erhält das KI-Ergebnis DIREKT zurück:
///  - KI bestätigt -> Team ist informiert, fertig.
///  - KI widerspricht -> der Meldende kann eskalieren (manuelle Prüfung),
///    falls die KI falsch liegt. Auch dann gehen Bild, Report und
///    KI-Ergebnis an das Team.
class ImageReportService {
  /// Maximal übertragene Bildgröße (Base64) - identisch zum Server-Limit.
  static const int _maxBase64 = 3 * 1024 * 1024;

  Future<ImageReportOutcome> reportChatImage({
    required String imageBase64,
    required String reportedUserId,
    required String reason,
    String details = '',
    bool escalate = false,
  }) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('Melden derzeit nicht verfügbar (keine Verbindung).');
    }
    if (imageBase64.length > _maxBase64) {
      throw StateError('Bild ist zu groß für die Meldung.');
    }

    final response = await SupabaseService.client.functions.invoke(
      'report-image',
      body: {
        'imageBase64': imageBase64,
        'reportedUserId': reportedUserId,
        'reason': reason,
        'details': details,
        'escalate': escalate,
      },
    );

    if (response.status != 200) {
      throw StateError(
        'Meldung fehlgeschlagen (Status ${response.status}). '
        'Bitte später erneut versuchen.',
      );
    }
    final data = (response.data as Map).cast<String, dynamic>();
    return ImageReportOutcome(
      aiAvailable: data['available'] == true,
      aiAgrees: data['nsfw'] == true,
      score: (data['score'] as num?)?.toDouble() ?? 0,
      operatorNotified: data['notified'] == true,
    );
  }
}

/// Provider für den [ImageReportService].
final imageReportServiceProvider = Provider<ImageReportService>((ref) {
  return ImageReportService();
});

/// Zeigt den Bild-Melde-Dialog mit KI-Vorprüfung und Direkt-Feedback.
///
/// Flow: Grund wählen -> Absenden (Bild + Grund gehen an die KI-Prüfung
/// und das Team) -> Ergebnis-Dialog:
///  - „KI bestätigt": fertig, Team informiert.
///  - „KI widerspricht": optional [Zur manuellen Prüfung] (Eskalation).
/// Parallel wird ein klassischer Report-Eintrag (user_reports) erzeugt,
/// damit die Meldung auch im Admin-Screen „Meldungen" auftaucht.
Future<void> showImageReportDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Message message,
  required String reportedUserId,
  required String reportedUserName,
}) async {
  // Bild-Bytes aus der Data-URL extrahieren (mediaUrl = data:image/...;base64,<bytes>).
  final mediaUrl = message.mediaUrl ?? '';
  final commaIdx = mediaUrl.indexOf(',');
  if (!mediaUrl.startsWith('data:') || commaIdx < 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dieses Bild kann leider nicht gemeldet werden.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  final imageBase64 = mediaUrl.substring(commaIdx + 1);
  if (imageBase64.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dieses Bild kann leider nicht gemeldet werden.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  ReportType? selectedType;
  final descriptionController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.flag_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Bild melden: $reportedUserName')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.smart_toy_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dieses Bild wird bei einer Meldung automatisch '
                          'von einer KI auf unangemessene Inhalte geprüft. '
                          'Du siehst das Ergebnis sofort. Das Bild, dein '
                          'Report und das KI-Ergebnis gehen an unser Team. '
                          'Chats sind sonst Ende-zu-Ende-verschlüsselt.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Wähle den Grund für die Meldung:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 12),
                RadioGroup<ReportType>(
                  groupValue: selectedType,
                  onChanged: (v) => setState(() => selectedType = v),
                  child: Column(
                    children: [
                      ...ReportType.values.map(
                        (type) => RadioListTile<ReportType>(
                          title: Text(type.label),
                          value: type,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Zusätzliche Details (optional)',
                    hintText: 'Was ist passiert?',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: selectedType == null
                ? null
                : () async {
                    Navigator.of(ctx).pop();
                    await _runAiCheck(
                      context: context,
                      ref: ref,
                      imageBase64: imageBase64,
                      reportedUserId: reportedUserId,
                      reportedUserName: reportedUserName,
                      reason: selectedType!.label,
                      details: descriptionController.text.trim(),
                    );
                  },
            child: const Text('Absenden'),
          ),
        ],
      ),
    ),
  );
}

/// Führt den KI-Check durch und zeigt das Ergebnis/Eskalations-Dialoge.
Future<void> _runAiCheck({
  required BuildContext context,
  required WidgetRef ref,
  required String imageBase64,
  required String reportedUserId,
  required String reportedUserName,
  required String reason,
  required String details,
}) async {
  // Parallel: Klassischen Report-Eintrag erzeugen (Admin-Sicht
  // „Meldungen"), damit die Bild-Meldung dort ebenfalls auftaucht.
  final reporterName = ref.read(profileProvider).name.isNotEmpty
      ? ref.read(profileProvider).name
      : AppConstants.currentUserId;
  unawaited(
    ref.read(reportServiceProvider).createReport(
          reporterId: AppConstants.currentUserId,
          reporterUserName: reporterName,
          reportedUserId: reportedUserId,
          reportedUserName: reportedUserName,
          type: ReportType.inappropriateContent,
          description: 'Bild-Meldung: $reason${details.isEmpty ? '' : ' – $details'}',
        ),
  );

  // Lade-Dialog (nicht abbrechbar - der Scan dauert wenige Sekunden).
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Bild wird geprüft…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Die KI prüft das gemeldete Bild.'),
          ],
        ),
      ),
    ),
  ));

  ImageReportOutcome outcome;
  try {
    outcome = await ref.read(imageReportServiceProvider).reportChatImage(
          imageBase64: imageBase64,
          reportedUserId: reportedUserId,
          reason: reason,
          details: details,
        );
  } catch (e) {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(); // Lade-Dialog schließen
    }
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Meldung fehlgeschlagen'),
          content: Text(
            e is StateError ? e.message : 'Bitte später erneut versuchen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  if (Navigator.of(context).canPop()) Navigator.of(context).pop();

  // Fall 1: KI bestätigt die Meldung.
  if (outcome.aiAvailable && outcome.aiAgrees) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.verified_user_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Meldung bestätigt')),
          ],
        ),
        content: Text(
          'Danke! Die KI stuft das Bild ebenfalls als unangemessen ein '
          '(Score ${(outcome.score * 100).toStringAsFixed(0)}%).'
          '${outcome.operatorNotified ? '\n\nBild, dein Report und das KI-Ergebnis wurden automatisch an unser Team gesendet.' : '\n\nHinweis: Das Team konnte nicht per E-Mail benachrichtigt werden - deine Meldung ist trotzdem gespeichert.'}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  // Fall 2: KI widerspricht ODER nicht verfügbar -> Eskalations-Option.
  final aiText = outcome.aiAvailable
      ? 'Die KI stuft das Bild NICHT als unangemessen ein '
          '(Score ${(outcome.score * 100).toStringAsFixed(0)}%). '
          'Falls sie damit falsch liegt, kannst du das Bild zur manuellen '
          'Prüfung durch unser Team weiterleiten.'
      : 'Die automatische KI-Prüfung ist gerade nicht verfügbar. '
          'Du kannst das Bild direkt zur manuellen Prüfung durch unser '
          'Team weiterleiten.';

  final escalate = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.psychology_alt_outlined,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('KI-Ergebnis')),
        ],
      ),
      content: Text(aiText),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Fertig'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Zur manuellen Prüfung'),
        ),
      ],
    ),
  );

  if (escalate != true || !context.mounted) return;

  // Eskalation: erneut senden (escalate=true) - Bild, Report und frisches
  // KI-Ergebnis gehen an das Team.
  try {
    await ref.read(imageReportServiceProvider).reportChatImage(
          imageBase64: imageBase64,
          reportedUserId: reportedUserId,
          reason: reason,
          details: details,
          escalate: true,
        );
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Weitergeleitet'),
          content: const Text(
            'Deine Meldung wurde zur manuellen Prüfung an unser Team '
            'weitergeleitet - inklusive Bild, deinem Report und dem '
            'KI-Ergebnis. Danke für deine Hilfe!',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[ImageReport] Eskalation fehlgeschlagen: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Weiterleitung fehlgeschlagen. Bitte später erneut versuchen.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
