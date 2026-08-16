import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/report_service.dart';
import 'package:wisp/services/photo_moderation_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';

/// Hilfsfunktion: Prueft, ob der aktuell eingeloggte Nutzer der Admin ist.
///
/// Die Admin-UUID wird via --dart-define=ADMIN_UUID=... beim Build gesetzt.
/// Ist sie nicht konfiguriert (leerer String), gibt die Funktion IMMER false
/// zurück — Admin-Funktionen sind dann deaktiviert (fail-safe).
bool isCurrentUserAdmin() {
  final adminId = AppConstants.adminUserId;
  // Fail-safe: Wenn die Admin-UUID nicht konfiguriert ist, kann NIEMAND
  // Admin sein — auch nicht versehentlich durch leere User-ID.
  if (adminId.isEmpty) return false;
  final userId = SupabaseService.currentUser?.id;
  if (userId == null) return false;
  return userId == adminId;
}

/// Geschuetzter Admin-Screen (nur fuer den Entwickler sichtbar).
///
/// Zeigt zwei Bereiche:
///  1) "Meldungen"   -> Lokale Reports (Hive)
///  2) "Bug-Reports" -> Lokale Bug-Reports
const String _reportsCollection = 'user_reports';
const String _bugCollection = 'bug_reports';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _serverAdminChecked = false;

  @override
  void initState() {
    super.initState();
    // Sofortige clientseitige Berechtigungsprüfung beim Öffnen.
    _enforceAdmin();
    // Zusätzliche serverseitige Prüfung (Defense-in-Depth).
    _checkServerAdmin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bei Auth-Wechsel (Logout/Login) erneut prüfen.
    _enforceAdmin();
  }

  void _enforceAdmin() {
    if (!isCurrentUserAdmin() && mounted) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    }
  }

  Future<void> _checkServerAdmin() async {
    if (!mounted) return;
    try {
      final result = await SupabaseService.client.rpc('is_current_user_admin');
      if (result != true && mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    } catch (e) {
      debugPrint('[AdminScreen] Server-Admin-Check fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _serverAdminChecked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isCurrentUserAdmin()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Zugriff verweigert')),
        body: const Center(
          child: Text('Du hast keine Berechtigung, diesen Bereich zu oeffnen.'),
        ),
      );
    }

    // Warte auf den serverseitigen Admin-Check, bevor der eigentliche
    // Admin-Bereich gerendert wird.
    if (!_serverAdminChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Bereich'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Meldungen', icon: Icon(Icons.flag)),
              Tab(text: 'Bug Reports', icon: Icon(Icons.bug_report)),
              Tab(text: 'Moderation', icon: Icon(Icons.photo_library)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Schliessen',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            _ReportList(collection: _reportsCollection, kind: _ReportKind.moderation),
            _ReportList(collection: _bugCollection, kind: _ReportKind.bug),
            _PhotoModerationList(),
          ],
        ),
      ),
    );
  }
}

enum _ReportKind { moderation, bug }

class _ReportList extends ConsumerWidget {
  const _ReportList({required this.collection, required this.kind});

  final String collection;
  final _ReportKind kind;

  String _formatTimestamp(DateTime? ts) {
    if (ts == null) return 'unbekannt';
    return DateFormat('dd.MM.yyyy HH:mm').format(ts);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = kind == _ReportKind.moderation
        ? ref.watch(reportServiceProvider).getPendingReports()
        : <dynamic>[];

    // Bug-Reports sind aktuell nicht über den Service abrufbar,
    // da sie nur noch als JSON-Log ausgegeben werden. Zeige einen
    // Platzhalter, bis eine zentrale Ablage (z.B. Supabase) integriert ist.
    final items = kind == _ReportKind.bug
        ? const [{'summary': 'Bug Reports werden aktuell nur lokal geloggt.', 'createdAt': null}]
        : reports.map((r) => r.toJson()).toList();

    if (items.isEmpty) {
      return const Center(
        child: Text('Keine Eintraege vorhanden.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final data = items[index] as Map<String, dynamic>;
        return _ReportCard(data: data, kind: kind, format: _formatTimestamp);
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.data,
    required this.kind,
    required this.format,
  });

  final Map<String, dynamic> data;
  final _ReportKind kind;
  final String Function(DateTime?) format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = data['createdAt'] is DateTime ? data['createdAt'] as DateTime : null;

    if (kind == _ReportKind.moderation) {
      final reportedName = data['reportedUserId'] as String? ?? '?';
      final reporterName = data['reporterId'] as String? ?? '?';
      final reason = data['type'] as String? ?? 'unbekannt';
      final description = (data['description'] as String? ?? '').trim();
      final status = data['status'] as String? ?? 'neu';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(
                    label: Text(status),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Gemeldet: $reportedName  (ID: ${data['reportedUserId'] ?? '?'})'),
              Text('Von: $reporterName  (ID: ${data['reporterId'] ?? '?'})'),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Details: $description'),
              ],
              const SizedBox(height: 6),
              Text(
                'Zeit: ${format(createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final summary = data['summary'] as String? ?? '(ohne Betreff)';
    final description = (data['description'] as String? ?? '').trim();
    final appVersion = data['appVersion'] as String? ?? '?';
    final deviceInfo = (data['deviceInfo'] as String? ?? '?').trim();
    final userId = data['userId'] as String? ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (description.isNotEmpty) Text(description),
            const SizedBox(height: 6),
            Text('App Version: $appVersion'),
            Text('Gerät/OS: $deviceInfo'),
            if (userId.isNotEmpty) Text('Nutzer ID: $userId'),
            const SizedBox(height: 6),
            Text(
              'Zeit: ${format(createdAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin-Tab: Foto-Moderation (Hugging Face pending reviews).
class _PhotoModerationList extends ConsumerStatefulWidget {
  const _PhotoModerationList();

  @override
  ConsumerState<_PhotoModerationList> createState() =>
      _PhotoModerationListState();
}

class _PhotoModerationListState extends ConsumerState<_PhotoModerationList> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = ref.read(photoModerationServiceProvider);
    _entries = await service.fetchPendingReviews();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approve(int id) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) return;
    final service = ref.read(photoModerationServiceProvider);
    await service.approvePhoto(id, adminId);
    await _load();
  }

  Future<void> _reject(int id) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) return;
    final service = ref.read(photoModerationServiceProvider);
    await service.rejectPhoto(id, adminId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_entries.isEmpty) {
      return const Center(child: Text('Keine ausstehenden Moderationen.'));
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = _entries[i];
        final userId = entry['user_id'] as String? ?? '?';
        final userName = entry['user']?['name'] as String? ?? userId;
        final hash = (entry['photo_hash'] as String? ?? '').substring(0, 12);
        final created = entry['created_at'] as String? ?? '';

        return ListTile(
          title: Text('$userName ($hash...)'),
          subtitle: Text(created),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                tooltip: 'Genehmigen',
                onPressed: () => _approve(entry['id'] as int),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Ablehnen',
                onPressed: () => _reject(entry['id'] as int),
              ),
            ],
          ),
        );
      },
    );
  }
}
