import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:wisp/models/message.dart';
import 'package:wisp/models/report_models.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/services/secure_hive.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';

/// Pseudonymisiert einen Identifier/Name mit SHA-256 (H-06).
///
/// Die Reporter-ID wird nur noch als Einweg-Hash gespeichert: Bei
/// Storage-Inspektion (verlorenes Gerät, Debug-Bridge) ist die Zuordnung
/// "Report → Nutzer" nicht mehr direkt lesbar. Die UUID hat hohe Entropie,
/// ein Brute-Force über den Hash ist praktisch ausgeschlossen.
String hashPii(String value) => sha256.convert(utf8.encode(value)).toString();

/// Service für Nutzer-Reports (Melden-Funktion).
///
/// Speichert Reports lokal in Hive UND übermittelt sie zentral an Supabase
/// (Tabelle user_reports, RPC submit_report). Nur über die Melde-Funktion
/// können Nachrichten den Support erreichen: Chats sind E2E/P2P und werden
/// nirgends gespeichert – der meldende Client entschlüsselt die letzten
/// 3 Nachrichten lokal und hängt sie an die Meldung an.
class ReportService {
  static const String _boxName = 'user_reports';

  late Box<UserReport> _box;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    // AES-verschlüsselt (Reports enthalten PII, s. SecureHive).
    _box = await SecureHive.instance.openBox<UserReport>(_boxName);
    _initialized = true;
  }

  Future<UserReport> createReport({
    required String reporterId,
    required String reporterUserName,
    required String reportedUserId,
    required String reportedUserName,
    required ReportType type,
    String? description,
    List<Message>? messages,
  }) async {
    final report = UserReport(
      // Nicht-deterministischer Hive-Key OHNE PII (X-M-07): Die User-IDs
      // dürfen nicht im Schlüssel auftauchen.
      id: 'report_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0xFFFFFF)}',
      // Reporter-ID nur als SHA-256-Hash speichern (X-M-08/H-06).
      reporterId: hashPii(reporterId),
      reportedUserId: reportedUserId,
      type: type,
      description: description,
      createdAt: DateTime.now(),
    );
    await _box.put(report.id, report);

    // Zentrale Ablage beim Support (best effort). Nur dieser Weg
    // übermittelt Nachrichten-Inhalte an Dritte – der Rest des Chats
    // bleibt Ende-zu-Ende-verschlüsselt auf den Geräten.
    unawaited(_submitToServer(report, messages));
    return report;
  }

  /// Übermittelt die Meldung inkl. der letzten (lokal entschlüsselten)
  /// Nachrichten an Supabase (Tabelle user_reports).
  Future<void> _submitToServer(
    UserReport report,
    List<Message>? messages,
  ) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.rpc(
        'submit_report',
        params: {
          'p_reported_user_id': report.reportedUserId,
          'p_report_type': report.type.value,
          'p_description': report.description,
          'p_messages': (messages ?? const <Message>[]).map((m) {
            return {
              'sender_id': m.senderId,
              'type': m.type.name,
              'text': m.text,
              'media_url': m.mediaUrl,
              'duration_seconds': m.durationSeconds,
              'sent_at': m.timestamp.toIso8601String(),
            };
          }).toList(),
        },
      );
      debugPrint('[ReportService] Meldung an den Support übermittelt.');
    } catch (e) {
      debugPrint('[ReportService] Server-Meldung fehlgeschlagen: $e');
    }
  }

  List<UserReport> getReportsByReporter(String reporterId) {
    final hash = hashPii(reporterId);
    return _box.values
        .where((r) => r.reporterId == hash)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<UserReport> getReportsAgainstUser(String userId) {
    return _box.values
        .where((r) => r.reportedUserId == userId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<UserReport> getPendingReports() {
    return _box.values
        .where((r) => r.status == 'pending')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<UserReport> getReportsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _box.values
        .where((r) => !r.createdAt.isBefore(start) && r.createdAt.isBefore(end))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> updateReportStatus(
    String reportId,
    String status, {
    String? moderatorNote,
  }) async {
    final report = _box.get(reportId);
    if (report != null) {
      await _box.put(reportId, report.copyWith(
        status: status,
        moderatorNote: moderatorNote,
        resolvedAt: status != 'pending' ? DateTime.now() : null,
      ));
    }
  }

  void dispose() {
    _box.close();
  }
}

/// Provider für den ReportService.
final reportServiceProvider = Provider<ReportService>((ref) {
  final service = ReportService();
  Future.microtask(() => service.initialize());
  ref.onDispose(service.dispose);
  return service;
});

/// Zeigt den Dialog zum Melden eines Nutzers.
///
/// [messages] sind optional die letzten Chat-Nachrichten (max. 3), die der
/// Meldung automatisch angehängt werden. Bei vorhandenen Nachrichten wird
/// dies im Dialog EXPLIZIT kenntlich gemacht: Chats sind E2E-verschlüsselt,
/// nur über eine Meldung kann der Support Inhalte einsehen.
Future<void> showReportUserDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String reportedUserId,
  required String reportedUserName,
  List<Message>? messages,
}) async {
  ReportType? selectedType;
  final descriptionController = TextEditingController();
  final attachedCount = messages?.length ?? 0;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Nutzer melden: $reportedUserName')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (attachedCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mit deiner Meldung werden automatisch die '
                            'letzten $attachedCount Nachrichten dieses Chats '
                            '(inklusive Bildern, Videos und '
                            'Sprachnachrichten) an unseren Support '
                            'übermittelt. Chats sind Ende zu Ende '
                            'verschlüsselt. Nur über eine Meldung kann der '
                            'Support Nachrichten einsehen.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Waehle den Grund fuer die Meldung:',
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
                      ...ReportType.values.map((type) => RadioListTile<ReportType>(
                        title: Text(type.label),
                        value: type,
                        contentPadding: EdgeInsets.zero,
                      )),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                    final reporterName =
                        ref.read(profileProvider).name.isNotEmpty
                            ? ref.read(profileProvider).name
                            : AppConstants.currentUserId;
                    await ref.read(reportServiceProvider).createReport(
                      reporterId: AppConstants.currentUserId,
                      reporterUserName: reporterName,
                      reportedUserId: reportedUserId,
                      reportedUserName: reportedUserName,
                      type: selectedType!,
                      description: descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                      messages: messages,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Meldung gesendet. Danke fuer deine Hilfe!')),
                      );
                    }
                  },
            child: const Text('Absenden'),
          ),
        ],
      ),
    ),
  );
}

/// Button zum Melden eines Nutzers (für Chat und Profil).
class ReportUserButton extends ConsumerWidget {
  const ReportUserButton({
    required this.reportedUserId,
    required this.reportedUserName,
    super.key,
  });

  final String reportedUserId;
  final String reportedUserName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.flag_outlined),
      tooltip: 'Nutzer melden',
      onPressed: () => showReportUserDialog(
        context: context,
        ref: ref,
        reportedUserId: reportedUserId,
        reportedUserName: reportedUserName,
      ),
    );
  }
}
