import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/photo_moderation_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
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

/// Geschuetzter Admin-Screen.
///
/// SCHUTZKONZEPT (warum normale Nutzer ihn nicht sehen koennen):
///  1. Route nur aus "Mein Profil" verlinkt; der Screen prueft beim Oeffnen
///     clientseitig [isCurrentUserAdmin] UND serverseitig den RPC
///     `is_current_user_admin` (fail-closed - bei Fehler wird umgeleitet).
///  2. Alle Daten kommen ausschliesslich aus SECURITY DEFINER-RPCs
///     (`admin_list_*`), die `is_current_user_admin()` serverseitig
///     pruefen. Ohne Admin-Flag liefern sie leere Ergebnisse bzw. Fehler -
///     selbst bei manipuliertem Client ist kein Datenzugriff moeglich.
///  3. Schreibaktionen (Verifizierungs-Freigabe) laufen durch die Edge
///     Function `verify-account`, die den Admin-Status ebenfalls
///     serverseitig gegen die profiles-Tabelle prueft.
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
    _enforceAdmin();
    _checkServerAdmin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
      if (mounted && result != true) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    } catch (e) {
      // Fail-closed (Audit H6): Schlägt die serverseitige Prüfung fehl,
      // wird der Admin-Bereich NICHT gerendert.
      if (kDebugMode) {
        debugPrint('[AdminScreen] Server-Admin-Check fehlgeschlagen '
            '(fail-closed): $e');
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
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

    if (!_serverAdminChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Bereich'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Meldungen', icon: Icon(Icons.flag)),
              Tab(text: 'Bug Reports', icon: Icon(Icons.bug_report)),
              Tab(text: 'Verifizierung', icon: Icon(Icons.verified)),
              Tab(text: 'Moderation', icon: Icon(Icons.photo_library)),
              Tab(text: 'Sperren', icon: Icon(Icons.block)),
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
            _UserReportsTab(),
            _BugReportsTab(),
            _VerificationTab(),
            _PhotoModerationList(),
            _BansTab(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Gemeinsames Lade-Geruest fuer Server-Listen.
// ===========================================================================
class _AsyncList extends StatelessWidget {
  const _AsyncList({
    required this.loading,
    required this.error,
    required this.items,
    required this.emptyText,
    required this.itemBuilder,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> items;
  final String emptyText;
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Fehler: $error'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) return Center(child: Text(emptyText));
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => itemBuilder(context, items[i]),
      ),
    );
  }
}

String _fmtTs(dynamic ts) {
  final dt = ts is DateTime
      ? ts
      : DateTime.tryParse(ts?.toString() ?? '') ;
  if (dt == null) return 'unbekannt';
  return DateFormat('dd.MM.yyyy HH:mm').format(dt);
}

// ===========================================================================
// Tab 1: Nutzer-Meldungen (user_reports-Tabelle via admin_list_user_reports)
// ===========================================================================
class _UserReportsTab extends ConsumerStatefulWidget {
  const _UserReportsTab();

  @override
  ConsumerState<_UserReportsTab> createState() => _UserReportsTabState();
}

class _UserReportsTabState extends ConsumerState<_UserReportsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchUserReports();
      // JSONB-Felder (createdAt als ISO-String) normalisieren.
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['createdAt'] =
            DateTime.tryParse('${copy['createdAt']}')?.toLocal();
        return copy;
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _resolve(String id) async {
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      await db.resolveUserReport(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konnte Meldung nicht abschliessen: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _items,
      emptyText: 'Keine Meldungen vorhanden.',
      onRetry: _load,
      itemBuilder: (context, data) {
        final theme = Theme.of(context);
        final type = data['reportType'] as String? ?? 'unbekannt';
        final description = (data['description'] as String? ?? '').trim();
        final status = data['status'] as String? ?? 'pending';
        final reportedId = data['reportedUserId'] as String? ?? '?';
        final reporterShort = '${data['reporterId'] ?? '?'}';
        final messagesCount =
            (data['messages'] as List<dynamic>? ?? <dynamic>[]).length;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      label: Text(status),
                      backgroundColor: status == 'pending'
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(type,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText('Gemeldeter Nutzer: $reportedId'),
                SelectableText(
                    'Reporter: ${reporterShort.length > 12 ? '${reporterShort.substring(0, 12)}…' : reporterShort} (gehasht)'),
                Text('$messagesCount Nachricht(en) beigelegt'),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText(description),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _fmtTs(data['createdAt']),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (status == 'pending')
                      TextButton(
                        onPressed: () =>
                            _resolve(data['id'] as String),
                        child: const Text('Bearbeitet'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Tab 2: Bug Reports (bug_reports-Tabelle via admin_list_bug_reports)
// ===========================================================================
class _BugReportsTab extends ConsumerStatefulWidget {
  const _BugReportsTab();

  @override
  ConsumerState<_BugReportsTab> createState() => _BugReportsTabState();
}

class _BugReportsTabState extends ConsumerState<_BugReportsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchBugReports();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['createdAt'] =
            DateTime.tryParse('${copy['createdAt']}')?.toLocal();
        return copy;
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _items,
      emptyText: 'Keine Bug Reports vorhanden.',
      onRetry: _load,
      itemBuilder: (context, data) {
        final theme = Theme.of(context);
        final description = (data['description'] as String? ?? '').trim();
        final deviceInfo = (data['deviceInfo'] as String? ?? '').trim();
        final attachments = data['attachmentCount'] as int? ?? 0;
        final userId = data['userId'] as String? ?? '';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(description.isNotEmpty
                    ? description
                    : '(ohne Beschreibung)',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text('Anhänge: $attachments · ${_fmtTs(data['createdAt'])}',
                    style: theme.textTheme.bodySmall),
                if (deviceInfo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(deviceInfo,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
                if (userId.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText('Nutzer: $userId',
                      style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Tab 3: Verifizierungen (Videos im privaten Bucket freigeben/ablehnen)
// ===========================================================================
class _VerificationTab extends ConsumerStatefulWidget {
  const _VerificationTab();

  @override
  ConsumerState<_VerificationTab> createState() => _VerificationTabState();
}

class _VerificationTabState extends ConsumerState<_VerificationTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String? _busyUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchPendingVerifications();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['submittedAt'] =
            DateTime.tryParse('${copy['submittedAt']}')?.toLocal();
        return copy;
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _review(String targetUserId, {required bool approve}) async {
    setState(() => _busyUserId = targetUserId);
    try {
      await SupabaseService.client.functions.invoke(
        'verify-account',
        body: {
          'action': 'review',
          'targetUserId': targetUserId,
          'isVerified': approve,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Review fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  /// Kurzlebige signierte URL vom Server holen und Video ansehen.
  Future<void> _watch(String targetUserId) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'verification-media',
        body: {'targetUserId': targetUserId},
      );
      final url = (response.data as Map?)?['url'] as String?;
      if (url == null) throw StateError('keine URL');
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Browser konnte URL nicht oeffnen');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video konnte nicht geladen werden: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _items,
      emptyText: 'Keine offenen Verifizierungen.',
      onRetry: _load,
      itemBuilder: (context, data) {
        final name = data['name'] as String? ?? '?';
        final userId = data['userId'] as String? ?? '?';
        final busy = _busyUserId == userId;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(name),
            subtitle: SelectableText(userId),
            trailing: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Video ansehen',
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed: () => _watch(userId),
                      ),
                      IconButton(
                        tooltip: 'Freigeben',
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => _review(userId, approve: true),
                      ),
                      IconButton(
                        tooltip: 'Ablehnen (Video wird geloescht)',
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => _review(userId, approve: false),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Tab 4: Foto-Moderation (unveraendert uebernommen, mit Hash-Guard)
// ===========================================================================
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
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = _entries[i];
        final userId = entry['user_id'] as String? ?? '?';
        final userName = entry['user']?['name'] as String? ?? userId;
        final hashFull = entry['photo_hash'] as String? ?? '';
        // Guard: kuerzerer Hash darf keinen RangeError werfen.
        final hash = hashFull.length > 12
            ? '${hashFull.substring(0, 12)}…'
            : hashFull;
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

// ===========================================================================
// Tab 5: Sperren (banned_emails, Anzeige)
// ===========================================================================
class _BansTab extends ConsumerStatefulWidget {
  const _BansTab();

  @override
  ConsumerState<_BansTab> createState() => _BansTabState();
}

class _BansTabState extends ConsumerState<_BansTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchBannedEmails();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['bannedAt'] =
            DateTime.tryParse('${copy['bannedAt']}')?.toLocal();
        return copy;
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      loading: _loading,
      error: _error,
      items: _items,
      emptyText: 'Keine Sperren vorhanden.',
      onRetry: _load,
      itemBuilder: (context, data) {
        final email = data['email'] as String? ?? '?';
        final reason = (data['reason'] as String? ?? '').trim();
        final bannedBy = data['bannedBy'] as String? ?? '?';
        return ListTile(
          title: SelectableText(email),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reason.isNotEmpty) SelectableText(reason),
              Text('${_fmtTs(data['bannedAt'])} · von $bannedBy'),
            ],
          ),
          leading: const Icon(Icons.block, color: Colors.red),
        );
      },
    );
  }
}
