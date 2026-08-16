import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/dating_hour_models.dart';
import 'package:wisp/providers/dating_hour_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/dating_hour/dating_hour_preferences_screen.dart'
    show genderPrefFromList;
import 'package:wisp/services/dating_hour_service.dart';
import 'package:wisp/services/notification_service.dart';
import 'package:wisp/services/server_time_service.dart';
import 'package:wisp/utils/constants.dart';

/// Haupt-Screen für den Dating Hour Event.
///
/// Zeigt das aktuelle/nächste Event aus Supabase, den Countdown bis zum Start
/// (verifizierte Serverzeit) und erlaubt Opt-in/Opt-out. Während des Events
/// wird bei einer aktiven Session ein "Zum Chat"-Button angezeigt.
class DatingHourEventScreen extends ConsumerStatefulWidget {
  const DatingHourEventScreen({super.key});

  @override
  ConsumerState<DatingHourEventScreen> createState() => _DatingHourEventScreenState();
}

class _DatingHourEventScreenState extends ConsumerState<DatingHourEventScreen> {
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  String? _reminderScheduledFor;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
    _startCountdown();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    // V: Regelmäßiger Refresh vom Server, damit Status-Wechsel (scheduled ->
    // active -> ended) und neu zugewiesene Sessions zeitnah angezeigt werden.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(currentDatingHourEventProvider);
    });
  }

  void _startCountdown() {
    // V: Countdown läuft auf verifizierter Serverzeit, nicht DateTime.now().
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Plant EINMALIG die Benachrichtigung "10 Minuten vor Beginn".
  ///
  /// Läuft über die lokale OS-Planung (zonedSchedule) und feuert damit
  /// AUCH bei geschlossener App. Nur wenn der Nutzer teilnimmt (Opt-in)
  /// wird erinnert. Der Einzel-Schalter "Dating Hour Erinnerung" wird
  /// zusätzlich geprüft.
  void _scheduleStartReminder(DatingHourEvent event, bool isParticipating) {
    if (!isParticipating) return;
    final settings = ref.read(settingsProvider);
    if (!settings.notifyDatingHour) return;

    final start = DateTime(
      event.eventDate.year,
      event.eventDate.month,
      event.eventDate.day,
      event.startHour,
      event.startMinute,
    );
    final remindAt = start.subtract(const Duration(minutes: 10));
    final now = ServerTimeService.instance.getVerifiedNow();
    if (remindAt.isBefore(now) || remindAt.difference(now) > const Duration(hours: 24)) {
      return;
    }

    final key = '${event.id}_${event.eventDate.toIso8601String()}';
    if (_reminderScheduledFor == key) return;
    _reminderScheduledFor = key;

    NotificationService.instance.scheduleAt(
      id: event.id.hashCode,
      when: remindAt,
      title: 'Dating Hour startet gleich',
      body: 'In 10 Minuten geht es los – sei dabei!',
      channelId: 'events',
    );
  }

  /// Entfernt eine geplante Erinnerung (z. B. nach Opt-out).
  void _cancelStartReminder(DatingHourEvent event) {
    NotificationService.instance.cancel(event.id.hashCode);
    _reminderScheduledFor = null;
  }

  Future<void> _joinEvent() async {
    // Explizite Bestätigung: Die Teilnahme darf NUR über diesen Flow
    // entstehen (kein automatischer Beitritt durch Refresh oder
    // Präferenzen-Speichern).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Am Event teilnehmen?'),
        content: const Text(
          'Du wirst nur dann mit jemandem verbunden, wenn du jetzt '
          'bestätigst. Du kannst bis zum Ende des Events jederzeit '
          'aussteigen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ich bin dabei'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final service = ref.read(datingHourServiceProvider);
    // Defaults aus der Einrichtung übernehmen (identisch zum
    // Präferenzen-Screen, solange der Nutzer dort nichts angepasst hat).
    final settings = ref.read(settingsProvider);
    final userPrefs = ref.read(userPreferencesProvider);
    final preferences = DatingHourPreferences(
      ageMin: settings.ageRangeMin.clamp(18, 99),
      ageMax: settings.ageRangeMax.clamp(18, 99),
      genderPreference: genderPrefFromList(userPrefs.genderPreferences),
      preferredTrait: 'Humor',
      maxDistanceKm: settings.maxDistanceKm.toDouble(),
    );
    try {
      await service.joinEvent(AppConstants.currentUserId, preferences);
      ref.invalidate(currentDatingHourEventProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Du nimmst am Dating Hour Event teil!')),
        );
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${e.message}')),
        );
      }
    }
  }

  Future<void> _leaveEvent() async {
    final service = ref.read(datingHourServiceProvider);
    try {
      final event = await service.getCurrentOrNextEvent();
      await service.leaveEvent(AppConstants.currentUserId);
      if (event != null) _cancelStartReminder(event);
      ref.invalidate(currentDatingHourEventProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Du hast das Event verlassen.')),
        );
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(currentDatingHourEventProvider);

    return eventAsync.when(
      loading: () => const _LoadingScreen(),
      error: (err, _) => _ErrorScreen(error: err.toString()),
      data: (event) {
        if (event == null) return const _NoEventScreen();
        return _buildEventContent(event);
      },
    );
  }

  Widget _buildEventContent(DatingHourEvent event) {
    // V: Status/Countdown-Properties von [event] verwenden intern
    // [ServerTimeService.instance.getVerifiedNow()], niemals DateTime.now().
    final isRunning = event.isRunningNow;
    final isEnded = event.isEnded;
    final isParticipating = event.currentUserParticipating;
    final canJoin = event.canJoin;
    final minutesUntilStart = event.minutesUntilStart;
    final minutesUntilEnd = event.minutesUntilEnd;

    // Erinnerung planen: Benachrichtigung genau 10 Minuten vor Beginn
    // (nur bei Teilnahme; feuert auch bei geschlossener App).
    if (!isRunning && !isEnded && minutesUntilStart > 0) {
      _scheduleStartReminder(event, isParticipating);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dating Hour'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Dating Hour wird via context.go(...) erreicht (kein Stack zum
          // poppen) -> zurück zum Entdecken-Tab navigieren.
          onPressed: () => context.go(AppRoutes.swipeModeSelection),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Event UND aktive Session neu laden.
              ref.invalidate(currentDatingHourEventProvider);
              ref.invalidate(myActiveDatingHourSessionProvider);
            },
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // B-05: Ohne verifizierte Server-Zeit sind Countdown/Status
            // manipulationsanfällig (lokale Uhr) — Nutzer transparent warnen.
            if (!ServerTimeService.instance.isVerified)
              const _ServerTimeWarningBanner(),
            _EventStatusCard(
              event: event,
              isRunning: isRunning,
              isEnded: isEnded,
              isParticipating: isParticipating,
              minutesUntilStart: minutesUntilStart,
              minutesUntilEnd: minutesUntilEnd,
            ),
            const SizedBox(height: 24),
            _buildActionArea(event, isRunning, isEnded, isParticipating, canJoin),
            const SizedBox(height: 24),
            const _EventInfoCard(),
            const SizedBox(height: 24),
            const _RulesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionArea(
    DatingHourEvent event,
    bool isRunning,
    bool isEnded,
    bool isParticipating,
    bool canJoin,
  ) {
    if (isEnded) {
      return const _PrimaryActionButton(
        icon: Icons.event_busy,
        label: 'Datinghour beendet',
        onPressed: null,
        color: Colors.grey,
      );
    }

    if (isRunning && isParticipating) {
      return _ActiveSessionButton(eventId: event.id);
    }

    if (isRunning && !isParticipating && canJoin) {
      return _PrimaryActionButton(
        icon: Icons.login,
        label: 'Jetzt beitreten & chatten',
        onPressed: _joinEvent,
        color: Colors.green,
      );
    }

    if (!isRunning && isParticipating) {
      return _PrimaryActionButton(
        icon: Icons.event_busy,
        label: 'Raus',
        onPressed: _leaveEvent,
        color: Colors.red,
      );
    }

    if (!isRunning && canJoin && !isParticipating) {
      return Column(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.tune),
            label: const Text('Präferenzen festlegen'),
            onPressed: () => context.go(AppRoutes.datingHourPreferences),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryActionButton(
            icon: Icons.event_available,
            label: 'Ich bin dabei',
            onPressed: _joinEvent,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      );
    }

    return _PrimaryActionButton(
      icon: Icons.schedule,
      label: 'Nächstes Event in ${_formatDuration(event.minutesUntilStart)}',
      onPressed: null,
      color: Colors.grey,
    );
  }
}

String _formatDuration(int minutes) {
  if (minutes < 60) return '$minutes Minuten';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '$h Stunden';
  return '$h Stunden $m Minuten';
}

/// Button, der die aktive Session des Users während eines Events anzeigt.
class _ActiveSessionButton extends ConsumerWidget {
  const _ActiveSessionButton({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(myActiveDatingHourSessionProvider(eventId));

    return sessionAsync.when(
      loading: () => const _PrimaryActionButton(
        icon: Icons.hourglass_top,
        label: 'Suche läuft...',
        onPressed: null,
        color: Colors.grey,
      ),
      error: (err, _) => const _PrimaryActionButton(
        icon: Icons.error_outline,
        label: 'Fehler beim Laden',
        onPressed: null,
        color: Colors.red,
      ),
      data: (session) {
        if (session == null) {
          return const _PrimaryActionButton(
            icon: Icons.search,
            label: 'Wir suchen gerade einen Partner...',
            onPressed: null,
            color: Colors.grey,
          );
        }
        return _PrimaryActionButton(
          icon: Icons.chat_bubble,
          label: 'Zum Chat',
          onPressed: () => context.go(AppRoutes.datingHourChatPath(session.id)),
          color: Colors.pink,
        );
      },
    );
  }
}

/// Warn-Banner, wenn die Server-Zeit (noch) nicht verifiziert ist (B-05).
class _ServerTimeWarningBanner extends StatelessWidget {
  const _ServerTimeWarningBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Die Server-Zeit konnte nicht verifiziert werden – '
              'Countdown und Status basieren auf der lokalen Gerätezeit.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ladebildschirm.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dating Hour')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Fehlerbildschirm.
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dating Hour')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Fehler beim Laden: $error',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hinweis, wenn kein Event verfügbar ist.
class _NoEventScreen extends StatelessWidget {
  const _NoEventScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dating Hour')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Aktuell ist kein Dating Hour Event geplant.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Status-Karte für das Event.
class _EventStatusCard extends StatelessWidget {
  const _EventStatusCard({
    required this.event,
    required this.isRunning,
    required this.isEnded,
    required this.isParticipating,
    required this.minutesUntilStart,
    required this.minutesUntilEnd,
  });

  final DatingHourEvent event;
  final bool isRunning;
  final bool isEnded;
  final bool isParticipating;
  final int minutesUntilStart;
  final int minutesUntilEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = isRunning
        ? 'LIVE: Dating Hour läuft!'
        : isEnded
            ? 'Datinghour beendet'
            : 'Nächste Datinghour am ${_formatDate(event.eventDate)}';

    return Card(
      color: isRunning ? colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning ? Icons.radio_button_checked : Icons.schedule,
                  color: isRunning
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isRunning ? colorScheme.onPrimaryContainer : null,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_pad(event.startHour)}:${_pad(event.startMinute)} bis ${_pad(event.endHour)}:${_pad(event.endMinute)} Uhr',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isRunning ? colorScheme.onPrimaryContainer : null,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InfoChip(
                  icon: Icons.people,
                  label: isParticipating ? 'Du nimmst teil' : 'Nicht angemeldet',
                  color: isRunning ? colorScheme.onPrimaryContainer : null,
                ),
                if (isRunning)
                  _InfoChip(
                    icon: Icons.timer,
                    label: 'Noch ${_formatDuration(minutesUntilEnd)}',
                    color: colorScheme.onPrimaryContainer,
                  )
                else if (!isEnded && minutesUntilStart > 0)
                  _InfoChip(
                    icon: Icons.timer,
                    label: 'Start in ${_formatDuration(minutesUntilStart)}',
                    color: colorScheme.primary,
                  ),
              ],
            ),
            if (!isRunning && !isEnded && minutesUntilStart > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 1 - (minutesUntilStart / (24 * 60)).clamp(0.0, 1.0),
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ],
            if (isParticipating) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRunning
                      ? colorScheme.onPrimaryContainer.withValues(alpha: 0.1)
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: isRunning
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Du nimmst teil! ${isRunning ? "Chats laufen." : "Warte auf den Start."}',
                        style: TextStyle(
                          color: isRunning
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const days = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  return '${days[date.weekday % 7]}, ${date.day}.${date.month}.${date.year}';
}

String _pad(int value) => value.toString().padLeft(2, '0');

/// Info-Chip Widget.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: effectiveColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

/// Primärer Aktions-Button.
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: onPressed != null ? color : Colors.grey,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Event-Info Karte.
class _EventInfoCard extends StatelessWidget {
  const _EventInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wie funktioniert Dating Hour?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            const _InfoRow(
              icon: Icons.favorite,
      title: 'Echter Chat statt Profil Check',
      subtitle: 'Keine Fotos, keine Bios, nur 5 Minuten echtes Gespräch.',
            ),
            const _InfoRow(
              icon: Icons.timer,
              title: '5 Minuten Zeit',
              subtitle: 'Danach entscheiden beide: "Annehmen" oder "Ablehnen".',
            ),
            const _InfoRow(
              icon: Icons.lock,
      title: 'Ende zu Ende verschlüsselt',
      subtitle: 'Eure Nachrichten lesen nur ihr, dank Signal Protocol.',
            ),
            const _InfoRow(
              icon: Icons.people,
              title: 'Live mit echten Personen',
              subtitle: 'Du wirst live mit einer anderen Person verbunden, die genau jetzt ebenfalls aktiv einen Dating Hour Partner sucht.',
            ),
            const _InfoRow(
              icon: Icons.refresh,
              title: 'Kein Match? Neue Chance!',
              subtitle: 'Bei "Ablehnen" sucht der Algorithmus sofort jemand Neues.',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Regeln-Karte.
class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wichtige Regeln',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
    const _RuleItem('1', 'Samstags 20:00 bis 21:00 Uhr (Beitritt bereits vorher möglich).'),
    const _RuleItem('2', 'Direkt in 1:1 Chat verbunden, ohne vorherige Profilansicht.'),
    const _RuleItem('3', '5 Minuten Chat, dann Entscheidung: "Annehmen" oder "Ablehnen".'),
    const _RuleItem('4', 'Nur bei BEIDSEITIGEM "Annehmen" entsteht ein Match.'),
    const _RuleItem('5', 'Bei "Ablehnen" (oder Timeout): Automatische neue Zuordnung.'),
    const _RuleItem('6', 'Während eines Chats: NUR dieser Chat erlaubt.'),
    const _RuleItem('7', 'Um 21:00 Uhr Ende, laufende Chats werden zu Ende geführt.'),
          ],
        ),
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem(this.number, this.text);
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
