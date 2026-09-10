import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/models/find_match_models.dart';
import 'package:wisp/models/match.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/find_your_match_service.dart';
import 'package:wisp/widgets/funke_overlay.dart';
import 'package:wisp/widgets/intro_audio_player.dart';
import 'package:wisp/widgets/states.dart';
import 'package:wisp/l10n/app_strings.dart';

/// Reiter "Interessen" mit drei Bereichen:
///   1. Eigene Likes (noch kein Match)
///   2. Erhaltene Likes (Vorstellung ansehen/anhören, Match bestätigen/ablehnen)
///   3. Matches (Quiz-Zugang, danach Chat)
class InteressenScreen extends ConsumerStatefulWidget {
  const InteressenScreen({super.key});

  @override
  ConsumerState<InteressenScreen> createState() => _InteressenScreenState();
}

class _InteressenScreenState extends ConsumerState<InteressenScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(L10n.t(context, 'interests.title')),
        bottom: TabBar(
          controller: _tabController,
          // Abgerundete Klick-Animation (kein eckiger Aufblitzer).
          splashBorderRadius: const BorderRadius.all(Radius.circular(24)),
          tabs: [
            Tab(text: L10n.t(context, 'interests.tabSent')),
            Tab(text: L10n.t(context, 'interests.tabReceived')),
            Tab(text: L10n.t(context, 'interests.tabSparks')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _OwnLikesTab(),
          _ReceivedLikesTab(),
          _MatchesTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Eigene Likes
// ---------------------------------------------------------------------------

class _OwnLikesTab extends ConsumerStatefulWidget {
  const _OwnLikesTab();

  @override
  ConsumerState<_OwnLikesTab> createState() => _OwnLikesTabState();
}

class _OwnLikesTabState extends ConsumerState<_OwnLikesTab> {
  List<ReceivedLike> _likes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _likes = await service.listMyLikes();
    } catch (e) {
      debugPrint('[Interessen] Eigene Likes fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeLike(ReceivedLike like) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client
          .from('likes')
          .delete()
          .eq('user_id', userId)
          .eq('liked_user_id', like.profile.id);
      if (mounted) {
        setState(() => _likes.removeWhere((l) => l.likeId == like.likeId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'interests.likeWithdrawn'))),
        );
      }
    } catch (e) {
      debugPrint('[Interessen] Like entfernen fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_likes.isEmpty) {
      return EmptyState(
        icon: Icons.favorite_border,
        title: L10n.t(context, 'interests.emptySentTitle'),
        message: L10n.t(context, 'interests.emptySentBody'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _likes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final like = _likes[i];
          final profile = like.profile;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(profile.name),
                    subtitle: Text([
                      '${profile.age ?? '?'} Jahre',
                      // Serverseitig berechnete Distanz (5-km-Schritte).
                      if (profile.distanceKm > 0) profile.distanceLabel,
                    ].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: L10n.t(context, 'interests.likeWithdrawTooltip'),
                      onPressed: () => _removeLike(like),
                    ),
                  ),
                  if (profile.introAudioPath != null) ...[
                    const SizedBox(height: 4),
                    IntroAudioPlayer(targetUserId: profile.id),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Erhaltene Likes
// ---------------------------------------------------------------------------

class _ReceivedLikesTab extends ConsumerStatefulWidget {
  const _ReceivedLikesTab();

  @override
  ConsumerState<_ReceivedLikesTab> createState() => _ReceivedLikesTabState();
}

class _ReceivedLikesTabState extends ConsumerState<_ReceivedLikesTab> {
  List<ReceivedLike> _likes = [];
  bool _loading = true;
  int? _busyLikeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _likes = await service.listReceivedLikes();
    } catch (e) {
      debugPrint('[Interessen] Erhaltene Likes fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(ReceivedLike like, {required bool accept}) async {
    if (_busyLikeId != null) return;
    setState(() => _busyLikeId = like.likeId);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      await service.respondToLike(like.likeId, accept: accept);
      if (!mounted) return;
      setState(() => _likes.removeWhere((l) => l.likeId == like.likeId));
      if (accept) {
        await FunkeOverlay.show(context);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? L10n.tf(context, 'interests.sparkAccepted',
                    {'name': like.profile.name})
                : L10n.tf(context, 'interests.likeDeclined',
                    {'name': like.profile.name}),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[Interessen] Antwort fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tf(context, 'common.errorWith', {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLikeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_likes.isEmpty) {
      return EmptyState(
        icon: Icons.favorite_border,
        title: L10n.t(context, 'interests.emptyReceivedTitle'),
        message: L10n.t(context, 'interests.emptyReceivedBody'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _likes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final like = _likes[i];
          final profile = like.profile;
          final busy = _busyLikeId == like.likeId;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.visibility_off,
                          color: Colors.white),
                    ),
                    title: Text([
                      '${profile.name}, ${profile.age ?? '?'}',
                      if (profile.distanceKm > 0) profile.distanceLabel,
                    ].join(' · ')),
                    subtitle: Text(
                      profile.introText.isNotEmpty
                          ? profile.introText
                          : L10n.t(context, 'interests.likedYou'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () =>
                        context.go(AppRoutes.profileDetailPath(profile.id)),
                  ),
                  if (profile.introAudioPath != null) ...[
                    const SizedBox(height: 8),
                    IntroAudioPlayer(targetUserId: profile.id),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              busy ? null : () => _respond(like, accept: false),
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: Text(L10n.t(context, 'interests.decline')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              busy ? null : () => _respond(like, accept: true),
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.favorite),
                          label: Text(L10n.t(context, 'interests.sparkConfirmBtn')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Matches
// ---------------------------------------------------------------------------

class _MatchesTab extends ConsumerStatefulWidget {
  const _MatchesTab();

  @override
  ConsumerState<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends ConsumerState<_MatchesTab> {
  List<MatchWithState> _serverMatches = [];
  bool _loading = true;

  /// Chats verwalten (v0.8.0): Mehrfachauswahl + "Aus Liste entfernen".
  bool _selectMode = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(findYourMatchServiceProvider);
      _serverMatches = await service.listMatchesWithState();
    } catch (e) {
      debugPrint('[Interessen] Matches laden fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelect(int matchId) {
    setState(() {
      if (!_selected.add(matchId)) {
        _selected.remove(matchId);
      }
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  Future<void> _hideSelected() async {
    final service = ref.read(findYourMatchServiceProvider);
    var failed = 0;
    for (final id in _selected) {
      try {
        await service.hideMatch(id);
      } catch (e) {
        debugPrint('[Interessen] hide fehlgeschlagen ($id): $e');
        failed++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failed == 0
              ? L10n.tf(context, 'interests.hiddenCount',
                  {'n': '${_selected.length}'})
              : L10n.tf(context, 'interests.hideFailed', {
                  'failed': '$failed',
                  'total': '${_selected.length}',
                })),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    _load();
  }

  /// "Re-Funke ohne Druck": gekühlte Verbindung mit einem Tap reaktivieren.
  Future<void> _respark(MatchWithState match) async {
    try {
      await ref.read(findYourMatchServiceProvider).resparkMatch(match.matchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(L10n.tf(context, 'interests.resparkDone', {'name': match.partner.name})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'interests.resparkFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Gespeichertes Profil (persistenter QR-Kontakt) entfernen - mit
  /// Bestätigung, da der zugehörige Chat/Verlauf mit verloren geht.
  Future<void> _deleteSavedProfile(
    BuildContext context,
    WidgetRef ref,
    Match contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'interests.deleteSavedTitle')),
        content: Text(L10n.tf(
          ctx,
          'interests.deleteSavedBody',
          {'name': contact.partner.name},
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'intro.discardKeep')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(L10n.t(ctx, 'intro.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !ref.context.mounted) return;
    ref.read(chatProvider.notifier).deleteQrContact(contact.id);
    if (ref.context.mounted) {
      ScaffoldMessenger.of(ref.context).showSnackBar(
        SnackBar(
          content: Text(L10n.tf(
              ref.context, 'profile.detail.savedRemoved',
              {'name': contact.partner.name})),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // QR-Kontakte sind nur lokal gespeichert (kein DB-Match).
    final qrContacts =
        ref.watch(chatProvider).where((m) => m.isQrContact).toList();

    // v0.8.0: aktive Funken oben, gekühlte ("Erschlossene Funken") unten -
    // ohne Countdown, ohne Ablauf-Benachrichtigung, ohne Verlängerungsdruck.
    final activeMatches =
        _serverMatches.where((m) => m.status == 'active').toList();
    final cooledMatches =
        _serverMatches.where((m) => m.status == 'cooled').toList();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_serverMatches.isEmpty && qrContacts.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: L10n.t(context, 'interests.emptySparksTitle'),
        message: L10n.t(context, 'interests.emptySparksBody'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (_serverMatches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  if (_selectMode) ...[
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selected.clear();
                          _selectMode = false;
                        });
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(L10n.t(context, 'common.cancel')),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _selected.isEmpty ? null : _hideSelected,
                      icon: const Icon(Icons.visibility_off, size: 18),
                      label: Text(L10n.tf(context, 'interests.hideSelected',
                          {'n': '${_selected.length}'})),
                    ),
                  ] else ...[
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() => _selectMode = true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(L10n.t(context, 'interests.manage')),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (qrContacts.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.bookmark,
              title: L10n.t(context, 'interests.savedTitle'),
              subtitle: L10n.t(context, 'interests.savedSub'),
            ),
            ...qrContacts.map((m) => ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text('${m.partner.name}, ${m.partner.age}'),
                  subtitle: Text(L10n.t(context, 'interests.savedTileSub')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.unreadCount > 0)
                        Badge.count(count: m.unreadCount),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        tooltip: L10n.t(context, 'qr.savedDeleteTooltip'),
                        onPressed: () =>
                            _deleteSavedProfile(context, ref, m),
                      ),
                    ],
                  ),
                  onTap: () {
                    ref.read(chatProvider.notifier).markRead(m.id);
                    context.go(AppRoutes.chatDetailPath(m.id));
                  },
                )),
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
          ],
          if (activeMatches.isNotEmpty) ...[
_SectionHeader(
icon: Icons.favorite,
title: L10n.t(context, 'interests.sparksTitle'),
subtitle: L10n.t(context, 'interests.matchesSub'),
),
            ...activeMatches.map((m) {
              if (_selectMode) {
                return CheckboxListTile(
                  value: _selected.contains(m.matchId),
                  onChanged: (_) => _toggleSelect(m.matchId),
                  title: Text('${m.partner.name}, ${m.partner.age ?? '?'}'),
                  secondary: const Icon(Icons.chat_bubble_outline),
                );
              }
              return _MatchTile(
                match: m,
                // v0.9.0-Feedback: "Auf die Person klicken -> kommt direkt
                // das Kennenlern-Quiz" - jetzt öffnet die Kachel IMMER den
                // Chat; das Quiz ist als Button im Chat erreichbar (es
                // schaltet nur das Foto frei).
                onTap: () =>
                    context.go(AppRoutes.chatDetailPath(m.matchId.toString())),
              );
            }),
          ],
          // "Erschlossene Funken" (v0.8.0): gekühlte Verbindungen, ganz
          // unten. KEIN Countdown, KEINE Ablauf-Benachrichtigung, KEINE
          // "jetzt verlängern!"-Aktion - nur der freiwillige Re-Funke.
          if (cooledMatches.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
            _SectionHeader(
              icon: Icons.archive_outlined,
              title: L10n.t(context, 'interests.cooledTitle'),
              subtitle: L10n.t(context, 'interests.cooledSub'),
            ),
            ...cooledMatches.map((m) => _CooledMatchTile(
                  match: m,
                  onOpen: () =>
                      context.go(AppRoutes.chatDetailPath(m.matchId.toString())),
                  onRespark: () => _respark(m),
                )),
          ],
        ],
      ),
    );
  }
}

/// Kachel für "Erschlossene Funken" (status = cooled): gedimmt, mit
/// Re-Funke-Button (ein Tap, ohne Frist, ohne Benachrichtigung).
class _CooledMatchTile extends StatelessWidget {
  const _CooledMatchTile({
    required this.match,
    required this.onOpen,
    required this.onRespark,
  });

  final MatchWithState match;
  final VoidCallback onOpen;
  final VoidCallback onRespark;

  @override
  Widget build(BuildContext context) {
    final p = match.partner;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.5),
      child: ListTile(
        onTap: onOpen,
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text('${p.name}, ${p.age ?? '?'}'),
        subtitle: Text(
          p.bio.isNotEmpty ? p.bio : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: FilledButton.tonalIcon(
          onPressed: onRespark,
          icon: const Icon(Icons.local_fire_department, size: 18),
          label: Text(L10n.t(context, 'interests.resparkBtn')),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
          const SizedBox(width: 8),
          Expanded(
            child: Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.onTap});

  final MatchWithState match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = match.partner;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 28,
          child: match.quizPassed
              ? const Icon(Icons.person)
              : const Icon(Icons.visibility_off),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text([
                '${p.name}, ${p.age ?? '?'}',
                if (p.distanceKm > 0) p.distanceLabel,
              ].join(' · ')),
            ),
            // KEINE Streaks/Flammen-Zählung (v0.9.0-Feedback).
          ],
        ),
        subtitle: Text(
          match.quizPassed
              ? L10n.t(context, 'interests.photoUnlocked')
              : match.createdVia == 'find_match'
                  ? L10n.t(context, 'interests.quizPending')
                  : p.bio.isNotEmpty
                      ? p.bio
                      : L10n.t(context, 'interests.noBio'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: match.quizGated
            ? const Icon(Icons.photo_outlined)
            : const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}
