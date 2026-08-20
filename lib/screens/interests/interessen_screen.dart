import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/models/find_match_models.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/find_your_match_service.dart';
import 'package:wisp/utils/formatters.dart';
import 'package:wisp/widgets/intro_audio_player.dart';
import 'package:wisp/widgets/states.dart';

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
        title: const Text('Interessen'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Eigene Likes'),
            Tab(text: 'Erhaltene Likes'),
            Tab(text: 'Matches'),
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
          const SnackBar(content: Text('Like zurückgezogen.')),
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
      return const EmptyState(
        icon: Icons.favorite_border,
        title: 'Du hast noch niemanden geliked',
        message:
            'Lerne Leute über ihre Vorstellung kennen ("Find your Match") '
            'oder swipe blind durch Profile.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
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
                    subtitle: Text('${profile.age ?? '?'} Jahre'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: 'Like zurückziehen',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Es ist ein Match mit ${like.profile.name}! 🎉 '
                    'Das Kennenlern-Quiz wartet auf euch.'
                : 'Like von ${like.profile.name} abgelehnt.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[Interessen] Antwort fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
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
      return const EmptyState(
        icon: Icons.favorite_border,
        title: 'Noch keine erhaltenen Likes',
        message:
            'Sobald dich jemand über seine Vorstellung mag, erscheint er hier '
            'und du entscheidest über Match oder Ablehnung.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
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
                    title: Text('${profile.name}, ${profile.age ?? '?'}'),
                    subtitle: Text(
                      profile.introText.isNotEmpty
                          ? profile.introText
                          : 'Hat dich geliked',
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
                          label: const Text('Ablehnen'),
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
                          label: const Text('Match bestätigen'),
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

  @override
  Widget build(BuildContext context) {
    // QR-Kontakte sind nur lokal gespeichert (kein DB-Match).
    final qrContacts =
        ref.watch(chatProvider).where((m) => m.isQrContact).toList();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_serverMatches.isEmpty && qrContacts.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'Noch keine Matches',
        message:
            'Bestätige erhaltene Likes, um Matches zu bekommen. Danach wartet '
            'das Kennenlern-Quiz auf euch.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (qrContacts.isNotEmpty) ...[
            const _SectionHeader(
              icon: Icons.qr_code_2,
              title: 'Kontakte',
              subtitle: 'Per QR Code verbunden',
            ),
            ...qrContacts.map((m) => ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text('${m.partner.name}, ${m.partner.age}'),
                  trailing: m.unreadCount > 0
                      ? Badge.count(count: m.unreadCount)
                      : Text(Formatters.relative(m.matchedAt)),
                  onTap: () {
                    ref.read(chatProvider.notifier).markRead(m.id);
                    context.go(AppRoutes.chatDetailPath(m.id));
                  },
                )),
            const SizedBox(height: 8),
            const Divider(indent: 16, endIndent: 16),
          ],
          if (_serverMatches.isNotEmpty) ...[
            const _SectionHeader(
              icon: Icons.favorite,
              title: 'Matches',
              subtitle: 'Bestätigte gegenseitige Likes',
            ),
            ..._serverMatches.map((m) => _MatchTile(
                  match: m,
                  onTap: () {
                    if (m.quizGated) {
                      context.go(AppRoutes.quizPath(m.matchId));
                    } else {
                      context.go(AppRoutes.chatDetailPath(m.matchId.toString()));
                    }
                  },
                )),
          ],
        ],
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
        title: Text('${p.name}, ${p.age ?? '?'}'),
        subtitle: Text(
          match.quizPassed
              ? 'Foto freigeschaltet'
              : match.createdVia == 'find_match'
                  ? 'Quiz offen: ${match.unlockLevel}/2'
                  : p.bio.isNotEmpty
                      ? p.bio
                      : 'Keine Bio',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: match.quizGated
            ? const Icon(Icons.lock_outline)
            : const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}
