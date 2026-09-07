import 'package:flutter/material.dart';

/// Musik-Genre-Katalog für "Geschmack & Matching" (v0.8.0, Migration 074).
///
/// Die Slugs sind die serverseitigen Werte (profiles.music_liked /
/// music_disliked, Migration 074) - NICHT umbenennen, sonst brechen
/// bestehende Profile. "instrumental" ist laut Roadmap Pflichtbestandteil.
class MusicGenre {
  const MusicGenre(this.slug, this.label);

  final String slug;
  final String label;
}

const kMusicGenres = <MusicGenre>[
  MusicGenre('pop', 'Pop'),
  MusicGenre('rock', 'Rock'),
  MusicGenre('indie', 'Indie'),
  MusicGenre('metal', 'Metal'),
  MusicGenre('punk', 'Punk'),
  MusicGenre('hip_hop', 'Hip-Hop'),
  MusicGenre('deutschrap', 'Deutschrap'),
  MusicGenre('rnb', 'R&B'),
  MusicGenre('soul', 'Soul'),
  MusicGenre('jazz', 'Jazz'),
  MusicGenre('blues', 'Blues'),
  MusicGenre('klassik', 'Klassik'),
  MusicGenre('instrumental', 'Instrumental'),
  MusicGenre('house', 'House'),
  MusicGenre('techno', 'Techno'),
  MusicGenre('rave_techno', 'Rave / Hard Techno'),
  MusicGenre('edm', 'EDM'),
  MusicGenre('reggae', 'Reggae'),
  MusicGenre('salsa_latin', 'Latin / Salsa'),
  MusicGenre('afrobeats', 'Afrobeats'),
  MusicGenre('k_pop', 'K-Pop'),
  MusicGenre('country', 'Country'),
  MusicGenre('folk', 'Folk'),
  MusicGenre('schlager', 'Schlager'),
  MusicGenre('volksmusik', 'Volksmusik'),
  MusicGenre('charts', 'Charts'),
];

String musicGenreLabel(String slug) {
  for (final g in kMusicGenres) {
    if (g.slug == slug) return g.label;
  }
  return slug;
}

/// Auswahl eines Musik-Geschmacks: Gemagte Genres (Mehrfachauswahl,
/// inkl. "Instrumental") + optional Genres, die man explizit nicht mag.
/// Ein Genre kann nicht gleichzeitig geliked UND disliked sein - ein
/// Klick auf das jeweils andere Feld zieht es dort zurück.
class MusicTasteEditor extends StatelessWidget {
  const MusicTasteEditor({
    required this.liked,
    required this.disliked,
    required this.onChanged,
    super.key,
  });

  final List<String> liked;
  final List<String> disliked;
  final void Function(List<String> liked, List<String> disliked) onChanged;

  void _toggle(String slug) {
    final nextLiked = [...liked];
    final nextDisliked = [...disliked];
    if (nextLiked.remove(slug)) {
      // war gemocht -> jetzt neutral
    } else if (nextDisliked.remove(slug)) {
      // war verneint -> jetzt neutral
    } else {
      nextLiked.add(slug);
    }
    onChanged(nextLiked, nextDisliked);
  }

  void _toggleDislike(String slug) {
    final nextLiked = [...liked];
    final nextDisliked = [...disliked];
    if (nextDisliked.remove(slug)) {
      // war verneint -> jetzt neutral
    } else if (nextLiked.remove(slug)) {
      // war gemocht -> jetzt verneint
      nextDisliked.add(slug);
    } else {
      nextDisliked.add(slug);
    }
    onChanged(nextLiked, nextDisliked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diese Genres mag ich',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in kMusicGenres)
              FilterChip(
                label: Text(genre.label),
                selected: liked.contains(genre.slug),
                onSelected: (_) => _toggle(genre.slug),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Diese Genres mag ich nicht (freiwillig)',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in kMusicGenres)
              if (disliked.contains(genre.slug))
                FilterChip(
                  label: Text(genre.label),
                  selected: true,
                  checkmarkColor: Theme.of(context).colorScheme.error,
                  selectedColor:
                      Theme.of(context).colorScheme.errorContainer,
                  onSelected: (_) => _toggleDislike(genre.slug),
                ),
            InputChip(
              avatar: const Icon(Icons.block, size: 16),
              label: const Text('Genre ausschließen…'),
              onPressed: () => _pickDislike(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDislike(BuildContext context) async {
    final remaining = kMusicGenres
        .where((g) => !liked.contains(g.slug) && !disliked.contains(g.slug))
        .toList();
    if (remaining.isEmpty) return;
    final slug = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final genre in remaining)
              ListTile(
                title: Text(genre.label),
                onTap: () => Navigator.of(ctx).pop(genre.slug),
              ),
          ],
        ),
      ),
    );
    if (slug != null) _toggleDislike(slug);
  }
}

/// Zeigt den Musik-Geschmack eines (fremden) Profils an. Gemeinsame
/// gemagte Genres mit dem Betrachter werden hervorgehoben, wenn
/// [commonWith] gesetzt ist.
class MusicTasteView extends StatelessWidget {
  const MusicTasteView({
    required this.liked,
    this.disliked = const <String>[],
    this.commonWith = const <String>[],
    super.key,
  });

  final List<String> liked;
  final List<String> disliked;
  final List<String> commonWith;

  @override
  Widget build(BuildContext context) {
    if (liked.isEmpty && disliked.isEmpty) {
      return const Text(
        'Kein Musik-Geschmack angegeben.',
        style: TextStyle(color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final slug in liked)
          Chip(
            label: Text(musicGenreLabel(slug)),
            backgroundColor: commonWith.contains(slug)
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
          ),
        for (final slug in disliked)
          Chip(
            label: Text(
              '${musicGenreLabel(slug)} ✕',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
          ),
      ],
    );
  }
}
