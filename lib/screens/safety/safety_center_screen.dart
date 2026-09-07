import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/report_service.dart';
import 'package:wisp/l10n/app_strings.dart';

/// Safety Center: zentrale Anlaufstelle bei Belästigung, Stalking oder
/// Bedrohung – mit externen Hilfsangeboten und In-App-Maßnahmen.
///
/// Alle externen Links öffnen bewusst im Systembrowser/Telefon-App
/// (url_launcher); die App selbst übermittelt dabei keine Nutzungsdaten.
class SafetyCenterScreen extends ConsumerStatefulWidget {
  const SafetyCenterScreen({super.key});

  @override
  ConsumerState<SafetyCenterScreen> createState() =>
      _SafetyCenterScreenState();
}

class _SafetyCenterScreenState extends ConsumerState<SafetyCenterScreen> {
  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'safety.linkFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emergency_outlined,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bei akuter Gefahr rufe sofort die Polizei: 110. '
                      'Du bist nicht allein. Die folgenden Stellen helfen '
                      'kostenlos und vertraulich.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Sofort Hilfe',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: const Text('Hilfetelefon „Gewalt gegen Frauen“'),
            subtitle: const Text('116 016 · kostenlos, 24/7, anonym'),
            trailing: const Icon(Icons.call),
            onTap: () => _open(context, Uri(scheme: 'tel', path: '116016')),
          ),
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: const Text('TelefonSeelsorge'),
            subtitle:
                const Text('0800 111 0 111 · kostenlos, 24/7'),
            trailing: const Icon(Icons.call),
            onTap: () => _open(context, Uri(scheme: 'tel', path: '08001110111')),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('klicksafe (Cybermobbing & Beratung)'),
            subtitle: const Text('klicksafe.de'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open(context, Uri.parse('https://www.klicksafe.de')),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Hilfetelefon Stalking (Weisser Ring)'),
            subtitle: const Text('weisser-ring.de · 116 006'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                _open(context, Uri.parse('https://weisser-ring.de')),
          ),
          const Divider(height: 32),
          Text('Schutz in WispDating',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ExpansionTile(
            leading: Icon(Icons.flag_outlined),
            title: Text('Jemanden melden'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Im Chat über das Flag-Symbol oben rechts oder per langem '
                  'Drücken auf ein Bild. Deine letzten Nachrichten werden '
                  'transparent als Kontext übermittelt und vom Support '
                  'persönlich geprüft.',
                ),
              ),
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.block_outlined),
            title: Text('Jemanden blockieren'),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Chat-Menü (drei Punkte) → Blockieren. Likes und Match '
                  'werden entfernt; künftige Interaktionen werden serverseitig '
                  'verhindert. Die Person erfährt nicht davon.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.lock_person_outlined),
            title: Text(L10n.t(context, 'safety.protectOwnImages')),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Bilder eingehender Nachrichten sind standardmäßig '
                  'verpixelt (Einstellungen → Sicherheit im Chat). Eigene '
                  'Fotos bleiben bis zum gegenseitigen Quiz-Erfolg '
                  'grundsätzlich verborgen.',
                ),
              ),
            ],
          ),
          const _BlockedUsersSection(),
          const SizedBox(height: 8),
          const _MyReportsSection(),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Meine Daten exportieren'),
            subtitle: const Text('JSON-Export aller gespeicherten Daten'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacy),
          ),
          const Divider(height: 32),
          Text('Stalking-Leitfaden',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Wenn dir jemand online (oder offline) nachstellt:\n'
            '1. Nicht antworten, Kontakt bewusst abbrechen.\n'
            '2. Alles dokumentieren: Screenshots mit Datum, Chatverlauf, '
            'Profilnamen.\n'
            '3. In-App blockieren und uns über die Melde-Funktion informieren. '
            'Wir können Accounts dauerhaft sperren.\n'
            '4. Passwörter ändern und 2FA aktivieren (Einstellungen).\n'
            '5. Bei Bedrohung oder Angst: Polizei (110) bzw. 116 006 kontaktieren.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Meine Meldungen (v0.8.0): Status-Feedback ohne Details zu Dritten.
class _MyReportsSection extends ConsumerStatefulWidget {
  const _MyReportsSection();

  @override
  ConsumerState<_MyReportsSection> createState() => _MyReportsSectionState();
}

class _MyReportsSectionState extends ConsumerState<_MyReportsSection> {
  List<MyReportEntry>? _reports;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reports = await _loadReports();
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
      if (mounted) setState(() => _reports = []);
    }
  }

  Future<List<MyReportEntry>> _loadReports() async {
    final response = await SupabaseService.client.rpc('list_my_reports');
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) =>
            MyReportEntry.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Meine Meldungen',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_reports == null)
          const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_reports!.isEmpty)
          const Text('Du hast bisher keine Meldungen geschrieben.',
              style: TextStyle(color: Colors.grey))
        else
          for (final report in _reports!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                report.status == 'pending'
                    ? Icons.hourglass_top
                    : Icons.check_circle_outline,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(report.reportType.isEmpty
                  ? 'Meldung'
                  : report.reportType),
              subtitle: Text(report.statusLabel),
            ),
      ],
    );
  }
}

/// Blockierte Nutzer (v0.8.0): Liste mit Entblocken.
class _BlockedUsersSection extends ConsumerStatefulWidget {
  const _BlockedUsersSection();

  @override
  ConsumerState<_BlockedUsersSection> createState() => _BlockedUsersSectionState();
}

class _BlockedUsersSectionState extends ConsumerState<_BlockedUsersSection> {
  List<BlockedUserEntry>? _blocked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response =
          await SupabaseService.client.rpc('list_blocked_users');
      final rows = (response as List<dynamic>? ?? <dynamic>[]);
      final blocked = rows
          .map((row) =>
              BlockedUserEntry.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      if (mounted) setState(() => _blocked = blocked);
    } catch (_) {
      if (mounted) setState(() => _blocked = []);
    }
  }

  Future<void> _unblock(BlockedUserEntry entry) async {
    try {
      await SupabaseService.client
          .rpc('unblock_user', params: {'p_blocked': entry.blockedUserId});
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entblocken fehlgeschlagen. Bitte erneut '
                'versuchen.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Blockierte Nutzer',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_blocked == null)
          const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_blocked!.isEmpty)
          const Text('Du hast niemanden blockiert.',
              style: TextStyle(color: Colors.grey))
        else
          for (final entry in _blocked!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block_outlined),
              title: Text(entry.name),
              trailing: TextButton(
                onPressed: () => _unblock(entry),
                child: const Text('Entblocken'),
              ),
            ),
      ],
    );
  }
}
