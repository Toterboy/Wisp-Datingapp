import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-Sprache (Deutsch/Englisch). Default: Deutsch. Der Startwert wird
/// in main() aus SharedPreferences als Override gesetzt; [saveLocale]
/// aktualisiert State + Persistenz.
final localeProvider = StateProvider<Locale>((ref) {
  return const Locale('de');
});

Future<void> saveLocale(WidgetRef ref, Locale locale) async {
  ref.read(localeProvider.notifier).state = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_locale', locale.languageCode);
}

/// Zentrale Übersetzungen für die aktuell vollständig zweisprachig
/// ausgelieferten Oberflächen (Login/Registrieren, Einstellungen,
/// Navigation, Home, zentrale Dialoge). Nicht abgedeckte Keys fallen
/// auf Deutsch zurück.
class L10n {
  L10n._();

  static Locale localeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_L10nScope>()?.locale ??
      const Locale('de');

  static String t(BuildContext context, String key) {
    final locale = localeOf(context).languageCode;
    return _strings[locale]?[key] ?? _strings['de']![key] ?? key;
  }

  /// Wie [t], ersetzt aber {platzhalter} im Text, z. B.
  /// tf(context, 'profile.edit.maxDistance', {'km': '42'}).
  static String tf(
    BuildContext context,
    String key,
    Map<String, String> params,
  ) {
    var s = t(context, key);
    params.forEach((k, v) {
      s = s.replaceAll('{$k}', v);
    });
    return s;
  }
}

/// InheritedWidget, das die aktive Locale an [L10n.t] verteilt.
class _L10nScope extends InheritedWidget {
  const _L10nScope({required this.locale, required super.child});

  final Locale locale;

  @override
  bool updateShouldNotify(_L10nScope oldWidget) => oldWidget.locale != locale;
}

/// Wrappt [child] und stellt die aktive Locale für [L10n.t] bereit.
class L10nScope extends ConsumerWidget {
  const L10nScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return _L10nScope(locale: locale, child: child);
  }
}

const Map<String, Map<String, String>> _strings = {
  'de': {
    // Auth
    'auth.login': 'Einloggen',
    'auth.register': 'Registrieren',
    'auth.name': 'Name',
    'auth.email': 'Email',
    'auth.password': 'Passwort',
    'auth.passwordHint': 'Mindestens 8 Zeichen',
    'auth.forgot': 'Passwort vergessen?',
    'auth.keepLoggedIn': 'Angemeldet bleiben',
    'auth.keepLoggedInSub':
        'Automatisch eingeloggt bleiben, wenn du die App schließt (empfohlen).',
    'auth.toRegister': 'Noch kein Konto? Registrieren',
    'auth.toLogin': 'Schon ein Konto? Einloggen',
    'auth.passkey': 'Mit Passkey anmelden',
    'auth.passkeyCreate': 'Passkey erstellen',
    'auth.captcha': 'Sicherheitscheck',
    'auth.registerTitle': 'Konto erstellen',
    'auth.welcomeBack': 'Willkommen zurück',
    'auth.birthDate': 'Geburtsdatum',
    'auth.birthDateHint': 'TT. MM. JJJJ',
    'auth.birthDatePick': 'Bitte auswählen',
    'auth.birthDateMissing': 'Bitte wähle dein Geburtsdatum.',
    'auth.gender': 'Geschlecht',
    'gender.male': 'Männlich',
    'gender.maleTrans': 'Männlich (F to M)',
    'gender.female': 'Weiblich',
    'gender.femaleTrans': 'Weiblich (M to F)',
    'gender.diverse': 'Divers',
    'gender.other': 'Eigenes / Anderes',
    'auth.passwordHintStrong': 'Mindestens 8 Zeichen, mit Groß- und '
        'Kleinbuchstaben, einer Zahl und einem Sonderzeichen',
    'auth.showPassword': 'Passwort anzeigen',
    'auth.hidePassword': 'Passwort verbergen',
    'auth.captchaRegister': 'Bitte schließe den Sicherheitscheck ab, um '
        'dich zu registrieren.',
    'auth.captchaLogin': 'Bitte schließe den Sicherheitscheck ab, um dich '
        'anzumelden.',
    'captcha.retry': 'Erneut versuchen',
    'language.german': 'Deutsch',
    'language.english': 'Englisch',
    // Navigation
    'nav.home': 'Aktuelles',
    'nav.discover': 'Entdecken',
    'nav.interests': 'Interessen',
    'nav.profile': 'Profil',
    // Settings (Kern)
    'settings.title': 'Einstellungen',
    'settings.appearance': 'Darstellung',
    'settings.system': 'System',
    'settings.light': 'Hell',
    'settings.dark': 'Dunkel',
    'settings.colors': 'Farbwelt',
    'settings.language': 'Sprache',
    'settings.notifications': 'Benachrichtigungen',
    'settings.push': 'Push Benachrichtigungen',
    'settings.pushEnable': 'Benachrichtigungen aktivieren',
    'settings.pushEnableSub':
        'Nachrichten, Likes, Funken und Event Erinnerungen',
    'settings.notifyMessages': 'Chat Nachrichten',
    'settings.notifyLikes': 'Neue Likes',
    'settings.notifyFunken': 'Neue Funken',
    'settings.notifyFunkenSub': 'Wenn ein Funke entsteht',
    'settings.notifyDatingHour': 'Dating Hour Erinnerung',
    'settings.notifyDatingHourSub':
        '10 Minuten vor Beginn, wenn du dabei bist',
    'settings.chatSafety': 'Sicherheit im Chat',
    'settings.blur': 'Bilder verpixelt anzeigen',
    'settings.e2e': 'E2E-Identität',
    'settings.backupCreate': 'Backup erstellen',
    'settings.backupRestore': 'Backup wiederherstellen',
    'settings.passkeyDiagnose': 'Passkey-Diagnose',
    'settings.privacyAccount': 'Datenschutz & Account',
    'settings.privacyAccountSub':
        'Gespeicherte Daten, Einwilligungen, Account löschen',
    'settings.pause': 'Profil pausieren',
    'settings.pauseSub':
        'Unsichtbar in Entdecken und Find your Match. Funken und Chats '
        'bleiben bestehen.',
    'settings.pauseActive':
        'Profil ist pausiert und für neue Personen unsichtbar.',
    'settings.pauseConfirmTitle': 'Profil pausieren?',
    'settings.pauseConfirmBody':
        'Dein Profil wird in Entdecken und Find your Match nicht mehr '
        'angezeigt. Bestehende Funken und Chats bleiben bestehen. Du kannst '
        'die Pause jederzeit beenden.',
    'settings.pauseConfirmBtn': 'Pausieren',
    'settings.pauseOn':
        'Profil pausiert. Du bist unsichtbar, bis du die Pause beendest.',
    'settings.pauseOff': 'Pause beendet. Dein Profil ist wieder sichtbar.',
    'settings.visEveryoneSub':
        'Dein Profil erscheint in Entdecken und Find your Match.',
    'settings.visMatchesSub':
        'Nur Personen, mit denen du einen Funken hast, sehen dein Profil.',
    'settings.visHiddenSub':
        'Pausenmodus: unsichtbar für alle neuen Personen. Funken und Chats '
        'bleiben bestehen.',
    'settings.visEveryone': 'Jeder',
    'settings.visMatchesOnly': 'Nur Funken',
    'settings.visHidden': 'Unsichtbar (Pausiert)',
    'mood.happy': 'Glücklich',
    'mood.relaxed': 'Entspannt',
    'mood.adventurous': 'Abenteuerlustig',
    'mood.flirty': 'Flirty',
    'mood.thoughtful': 'Nachdenklich',
    'mood.tired': 'Müde',
    'theme.classic': 'Classic WispDating',
    'theme.ocean': 'Ozean',
    'theme.forest': 'Wald',
    'theme.sunset': 'Sonnenuntergang',
    'theme.lavender': 'Lavendel',
    'theme.slate': 'Schiefer',
    'theme.colorScheme': 'Farbschema',
    'dm.discovery': 'Entdecken',
    'dm.discoveryDesc': 'Profile entdecken, Funken versenden, chatten',
    'dm.findMatch': 'Find your Match',
    'dm.findMatchDesc': 'Vorstellung anhören oder lesen, dann entscheiden',
    'dm.randomChat': 'Zufallschat',
    'dm.randomChatDesc': 'Direkter Text-Chat mit zufällig passender Person',
    'dm.qrScan': 'QR-Code scannen',
    'dm.qrScanDesc': 'Code einer Person scannen und direkt verbinden',
    'dm.datingHour': 'Dating Hour (Event)',
    'dm.datingHourDesc':
        'Samstags 20 bis 21 Uhr: 5-Minuten-Chats mit Entscheidungsphase',
    'dm.transitSpark': 'Transit Spark',
    'dm.transitSparkDesc':
        'Blicke getauscht, sich nicht getraut? Später funken - auch wenn '
        'ihr längst weitergefahren seid.',
    'dm.groupMeet': 'Menschen kennenlernen',
    'dm.groupDirect': 'Direkt verbinden',
    'dm.groupOnTheGo': 'Unterwegs',
    'dm.pickHint': 'Wähle einen Modus, um neue Leute zu entdecken:',
    'common.new': 'NEU',
    'transit.title': 'Transit Spark',
    'transit.start': 'Radar aktivieren',
    'transit.stop': 'Radar stoppen',
    'transit.active': 'Radar aktiv - du bist sichtbar für Wisp-Geräte in der Nähe.',
    'transit.inactive': 'Radar aus. Aktiviere es, wenn du unterwegs bist.',
    'transit.remaining': 'Noch {time} aktiv',
    'transit.seenCount': '{count} Wisp-Geräte in Reichweite gesehen.',
    'transit.exchanged': 'Blicke getauscht',
    'transit.modeLabel': 'Wo bist du?',
    'transit.mode.transit': 'Bahn / Café',
    'transit.mode.convention': 'Messe / Event',
    'transit.modeHint':
        'Messe-Modus: nur starke Signale zählen (echter Sichtkontakt in '
        'dichten Umgebungen).',
    'transit.sheetTitle': 'Wer war das?',
    'transit.sheetHint':
        'Wähle 1-3 Merkmale, die dir an der Person aufgefallen sind - '
        'die Auswahl schärft das Matching.',
    'transit.sheetSend': 'Funken',
    'transit.tag.black_hoodie': 'Schwarzer Hoodie',
    'transit.tag.jacket': 'Jacke',
    'transit.tag.cap': 'Cap',
    'transit.tag.glasses': 'Brille',
    'transit.tag.headphones': 'Kopfhörer',
    'transit.tag.backpack': 'Rucksack',
    'transit.tag.tote_bag': 'Tote Bag',
    'transit.tag.lanyard': 'Lanyard / Badge',
    'transit.tag.scarf': 'Schal',
    'transit.tag.colorful_top': 'Auffälliges Oberteil',
    'transit.stored':
        'Signal gespeichert. Wenn die Person denselben Moment spürt und '
        'ebenfalls funkt, matcht ihr euch.',
    'transit.matchTitle': 'Funke übergesprungen!',
    'transit.matchBody':
        'Die Person hat denselben Moment gespürt. Schaut in eure Funken - '
        'ihr könnt jetzt chatten.',
    'transit.later': 'Später',
    'transit.openSparks': 'Zu den Funken',
    'transit.startFailed':
        'Radar konnte nicht gestartet werden. Bluetooth an und Berechtigung '
        'erteilen.',
    'transit.sendFailed': 'Signal konnte nicht gesendet werden. Bitte erneut.',
    'transit.howTitle': 'Wie funktioniert das?',
    'transit.howBody':
        'Aktiviere das Radar, wenn du unterwegs bist (Zug, Café, Messe). '
        'Dein Gerät tauscht mit anderen Wisp-Geräten in nächster Nähe '
        'anonyme, zufällige Token aus - ohne Namen, ohne Standort, ohne '
        'Fotos. Tippe später auf "Blicke getauscht": Spürt die andere '
        'Person denselben Moment und funkt ebenfalls, entsteht ein Funke.',
    'transit.privacyNote':
        'Tokens sind zufällig, rotieren regelmäßig und verfallen nach '
        '45 Minuten. Gespeichert wird nur, was du aktiv sendest - nichts '
        'verlässt dein Gerät, solange du nicht selbst funkt.',
    'transit.teenNote':
        'Unter 18? Du siehst ausschließlich altersseitig kompatible '
        'Nutzer - serverseitig erzwungen.',
    'onboarding.appbarTitle': 'Kurz kennengelernt',
    'onboarding.skipAll': 'Überspringen',
    'onboarding.fillLater': 'Später ausfüllen',
    'onboarding.next': 'Weiter',
    'onboarding.hello.title': 'Hi, ich bin Wisp!',
    'onboarding.hello.body':
        'In den nächsten Minuten richten wir dein Profil zusammen - '
        'als kurzes Gespräch statt Formular. Alles ist überspringbar, '
        'nichts ist falsch.',
    'onboarding.blind.title': 'Persönlichkeit vor Aussehen',
    'onboarding.blind.body':
        'Standardmäßig siehst du zuerst nur Name, Alter, Bio und '
        'Interessen - keine Fotos. So entscheidest du mit dem Kopf, '
        'nicht nur mit den Augen. Jederzeit abschaltbar.',
    'onboarding.connections.title': 'Echte Verbindungen',
    'onboarding.connections.body':
        'Ein Funke entsteht nur, wenn ihr euch beide wählt. Erst dann '
        'werden Fotos freigeschaltet und ihr könnt loschatten - fair '
        'statt oberflächlich.',
    'onboarding.q.bio':
        'Was macht dich aus? Erzähl kurz etwas von dir - was du liebst, '
        'was dich bewegt, was dich lustig findest.',
    'onboarding.q.bioHint': 'Ein paar ehrliche Sätze reichen völlig …',
    'onboarding.q.interests':
        'Womit verbringst du gerne Zeit? Wähle ein paar Interessen - '
        'daraus entstehen später gemeinsame Themen und Funken.',
    'onboarding.q.photo':
        'Magst du ein Profilbild von dir zeigen? Kein Stress - Fotos '
        'sind bei uns ohnehin erst nach einem Funke sichtbar.',
    'onboarding.photoLater': 'Du kannst später ein Profilbild hochladen.',
    'onboarding.q.habits':
        'Und wie stehst du zu Rauchen, Alkohol und Co.? ',
    'onboarding.q.habitsHint':
        'Diese Angaben fließen in dein Matching ein: Du siehst nur '
        'Personen, die maximal so viel konsumieren wie du.',
    'onboarding.done.title': 'Geschafft - schön, dass du da bist!',
    'onboarding.done.body':
        'Dein Profil steht. Alles kannst du später jederzeit in den '
        'Einstellungen ändern. Viel Spaß beim Entdecken!',
    'chathist.tileTitle': 'Chat-Verlauf lokal speichern',
    'chathist.mode.off': 'Aus',
    'chathist.mode.cap200': 'An (200 Nachrichten)',
    'chathist.mode.all': 'An (kompletter Verlauf)',
    'chathist.tileSubPrefix': 'Verschlüsselt (AES-256) auf diesem Gerät.',
    'chathist.deleteHint': 'Deaktivieren löscht die Historie.',
    'chathist.dialogTitle': 'Chat-Verlauf speichern',
    'chathist.modeWord': 'Modus:',
    'chat.safetyNumber': 'Sicherheitsnummer',
    'chat.safetyNumberTooltip': 'Sicherheitsnummer (E2E-Verifikation)',
    'chat.safetyChangedTitle': 'Sicherheitsnummer hat sich geändert',
    'chat.safetyChangedBody':
        'Der Verschlüsselungsschlüssel deines Kontakts hat sich geändert. '
        'Das kann nach einer Neuinstallation passieren - oder darauf '
        'hindeuten, dass sich jemand in die Verbindung einschleichen '
        'will.\n\nVergleiche die Sicherheitsnummer über einen zweiten '
        'Kanal (z. B. Anruf oder persönlich), bevor du fortfährst.',
    'chat.safetyChangedCancel': 'Abbrechen',
    'chat.safetyChangedAccept': 'Nummer geprüft: akzeptieren',
    'chat.reconnectStillFailing': 'Verbindung weiterhin fehlgeschlagen.',
    'chat.imageSourcePrompt': 'Wähle eine Quelle für das zu sendende Bild.',
    'chat.identityVerifiedTitle': 'Identität bestätigt',
    'chat.close': 'Schließen',
    'chat.coolSpark': 'Funke kühlen',
    'chat.coolSparkError': 'Funke konnte nicht gekühlt werden: {error}',
    'chat.coolSparkDone': 'Funke gekühlt – ihr findet euch unter „Erschlossene Funken" wieder.',
    'chat.backToSparks': 'Zurück zu den Funken',
    'chat.closeImageHint': 'Schließen (Bild kann danach nicht mehr angesehen werden)',
    'settings.backupChoosePw': 'Backup-Passwort wählen',
    'settings.restoreConfirmTitle': 'Identität wiederherstellen?',
    'settings.backupPasteCode': 'Backup-Code einfügen',
    'settings.restored': 'E2E-Identität wiederhergestellt.',
    'settings.codeInvalid': 'Ungültiger oder abgelaufener Code.',
    'settings.passkeyDeleteTitle': 'Passkey löschen?',
    'settings.delete': 'Löschen',
    'settings.passkeyDeleted': 'Passkey gelöscht.',
    'settings.deleteFailed': 'Löschen fehlgeschlagen.',
    'dh.prefs.setBtn': 'Präferenzen festlegen',
    'dh.nextEventIn': 'Nächstes Event in',
    'dh.searching': 'Suche läuft...',
    'dh.feature.noPhotos': 'Keine Fotos, keine Bios, nur 5 Minuten echtes Gespräch.',
    'dh.feature.e2eTitle': 'Ende zu Ende verschlüsselt',
    'dh.feature.e2eSub': 'Niemand außer euch beiden kann eure Nachrichten lesen (Signal-Protokoll).',
    'dh.prefs.savedHint': 'Präferenzen gespeichert. Deine Teilnahme meldest du über "Ich bin dabei" am Event-Tag an.',
    'report.detailsOptional': 'Zusätzliche Details (optional)',
    'report.checkingTitle': 'Bild wird geprüft…',
    'report.checkingSub': 'Die KI prüft das gemeldete Bild.',
    'report.retryLater': 'Bitte später erneut versuchen.',
    'report.confirmed': 'Meldung bestätigt',
    'report.forwardBtn': 'Zur manuellen Prüfung',
    'report.forwardFailed': 'Weiterleitung fehlgeschlagen. Bitte später erneut versuchen.',
    'interests.likeWithdrawn': 'Like zurückgezogen.',
    'interests.likeWithdrawTooltip': 'Like zurückziehen',
    'interests.sparkConfirmBtn': 'Funke bestätigen',
    'interests.resparkDone': 'Funke mit {name} glüht wieder ✨',
    'interests.matchesSub': 'Bestätigte gegenseitige Likes',
    'qr.openingChat': 'Chat mit {name} wird geöffnet...',
    'qr.enterFullCode': 'Bitte gib den vollständigen 8 stelligen Code ein.',
    'qr.resolveFailed': 'Code konnte nicht aufgelöst werden.',
    'qr.shareSub': 'Damit andere dich finden können',
    'qr.scanSub': 'Kamera öffnen und Code einscannen',
    'qr.myCode': 'Mein QR Code',
    'qr.yourCode': 'Dein Code',
    'qr.copyTooltip': 'Code kopieren',
    'qr.copied': 'Code in die Zwischenablage kopiert',
    'qr.shareHint': 'Teile diesen Code oder den QR Code mit anderen. Sie können dich damit in der App finden und direkt anschreiben.',
    'meet.metTitle': 'Schön, dass ihr euch getroffen habt! 🎉',
    'meet.youWant': 'Du möchtest dich treffen',
    'meet.theyWant': '{name} würde sich gerne mit dir treffen',
    'meet.later': 'Vielleicht später',
    'meet.ideas': 'Ideen für ein erstes Treffen:',
    'home.settingsTooltip': 'Einstellungen & Privatsphäre',
    'home.discoverSub': 'Lerne Leute über ihre Vorstellung kennen.',
    'home.likesSub': 'Likes führen zu Funken, wenn beide sich mögen.',
    'random.partnerLeft': 'Dein Gesprächspartner hat den Zufallschat verlassen.',
    'random.backToDiscover': 'Zurück zu Entdecken',
    'random.connecting': 'Partner gefunden! Verbinde verschlüsselt…',
    'profile.detail.unavailable': 'Dieses Profil ist derzeit nicht verfügbar.',
    'safety.linkFailed': 'Konnte Link nicht öffnen.',
    'safety.protectOwnImages': 'Eigene Bilder schützen',
    'safety.protectOwnImagesBody':
        'Bilder eingehender Nachrichten sind standardmäßig verpixelt '
        '(Einstellungen - Sicherheit im Chat). Eigene Fotos bleiben bis '
        'zum gegenseitigen Quiz-Erfolg grundsätzlich verborgen.',
    'home.noMessages': 'Keine neuen Nachrichten',
    'home.noMessagesSub': 'Wenn du Funken hast, erscheinen hier neue Nachrichten.',
    'safety.sectionHelp': 'Sofort Hilfe',
    'safety.hotline1': 'Hilfetelefon "Gewalt gegen Frauen"',
    'safety.hotline1Sub': '116 016 - kostenlos, 24/7, anonym',
    'safety.hotline2': 'TelefonSeelsorge',
    'safety.hotline2Sub': '0800 111 0 111 - kostenlos, 24/7',
    'safety.hotline3': 'klicksafe (Cybermobbing & Beratung)',
    'safety.hotline3Sub': 'klicksafe.de',
    'safety.hotline4': 'Hilfetelefon Stalking (Weisser Ring)',
    'safety.hotline4Sub': 'weisser-ring.de - 116 006',
    'safety.sectionProtect': 'Schutz in WispDating',
    'safety.reportSomeone': 'Jemanden melden',
    'safety.reportSomeoneBody':
        'Im Chat über das Flag-Symbol oben rechts oder per langem Drücken '
        'auf ein Bild. Deine letzten Nachrichten werden transparent als '
        'Kontext übermittelt und vom Support persönlich geprüft.',
    'safety.blockSomeone': 'Jemanden blockieren',
    'safety.blockSomeoneBody':
        'Chat-Menü (drei Punkte) - Blockieren. Likes und Funken werden '
        'entfernt; künftige Interaktionen werden serverseitig verhindert. '
        'Die Person erfährt nicht davon.',
    'safety.stalkingGuide': 'Stalking-Leitfaden',
    'safety.stalkingBody':
        'Wenn dir jemand online (oder offline) nachstellt: 1. Nicht '
        'antworten, Kontakt bewusst abbrechen. 2. Alles dokumentieren: '
        'Screenshots mit Datum, Chatverlauf, Profilnamen. 3. In-App '
        'blockieren und uns über die Melde-Funktion informieren. Wir '
        'können Accounts dauerhaft sperren. 4. Passwörter ändern und 2FA '
        'aktivieren (Einstellungen). 5. Bei Bedrohung oder Angst: Polizei '
        '(110) bzw. 116 006 kontaktieren.',
    'safety.exportData': 'Meine Daten exportieren',
    'safety.exportDataSub': 'JSON-Export aller gespeicherten Daten',
    'spice.answerSent': 'Antwort gesendet. Dein Gegenüber antwortet bald.',
    'spice.answerEdit': 'Antwort ändern',
    'spice.answer': 'Antworten',
    'bugreport.sendFailed': 'Übermittlung fehlgeschlagen. Bitte versuche es später erneut.',
    'home.noLikes': 'Keine neuen Likes',
    'home.noSparks': 'Keine neuen Funken',
    'interests.sparksTitle': 'Funken',
    'dh.feature.realChat': 'Echter Chat statt Profil Check',
    'dh.info.title': 'Wie funktioniert Dating Hour?',
    'dh.info.timeTitle': '5 Minuten Zeit',
    'dh.info.timeSub': 'Danach entscheiden beide: "Annehmen" oder "Ablehnen".',
    'dh.info.liveTitle': 'Live mit echten Personen',
    'dh.info.liveSub': 'Du wirst live mit einer anderen Person verbunden, die genau jetzt ebenfalls aktiv einen Dating Hour Partner sucht.',
    'dh.info.retryTitle': 'Kein Funke? Neue Chance!',
    'dh.info.retrySub': 'Bei "Ablehnen" sucht der Algorithmus sofort jemand Neues.',
    'chathist.off.title': 'Gar nichts (nur Arbeitsspeicher)',
    'chathist.cap200.title': '200 Nachrichten pro Chat',
    'chathist.all.title': 'Kompletter Verlauf',
    'chathist.off.sub': 'Chats sind nach dem Neustart weg.',
    'chathist.cap200.sub': 'Verschlüsselt, max. 200 pro Chat.',
    'chathist.all.sub': 'Verschlüsselt, ohne Limit.',
    'profile.menu.edit': 'Profil bearbeiten',
    'profile.menu.editSub': 'Daten, Interessen und Vorstellung ändern',
    'profile.menu.preview': 'Profil Vorschau',
    'profile.menu.previewSub': 'So sehen dich andere',
    'profile.menu.introPreview': 'Vorstellung Vorschau',
    'profile.menu.introPreviewSub': 'Deine Text- und Audio-Vorstellung ansehen',
    'profile.preview.title': 'Profil Vorschau',
    'profile.preview.hint': 'So sehen dich andere Nutzer (inkl. Altersschutz & Blind Mode):',
    'profile.preview.photoHidden': 'Deine Fotos sind aufgrund deiner Einstellungen (Persönlichkeit vor Aussehen / Altersschutz) für andere nicht sichtbar.',
    'profile.preview.aboutMe': 'Über mich',
    'profile.preview.noBio': 'Noch keine Bio.',
    'profile.preview.interests': 'Interessen',
    'profile.preview.note': 'Hinweis: Die tatsächliche Sichtbarkeit hängt vom Alter und den Einstellungen der jeweiligen Betrachter ab.',
    'profile.preview.type': 'Typ',
    'profile.intro.title': 'Meine Vorstellung',
    'profile.intro.empty': 'Du hast noch keine Text-Vorstellung hinterlegt.',
    'profile.intro.hint': 'Andere lernen dich über diese Vorstellung kennen, bevor sie ein Foto sehen. Bearbeiten kannst du sie unter Profil bearbeiten.',
    'profile.intro.audioEmpty': 'Noch keine Audio-Vorstellung hinterlegt.',
    'profile.intro.audioMissing': 'Audio-Vorstellung nicht gefunden.',
    'profile.intro.audioLoadError': 'Audio-Vorstellung konnte nicht geladen werden.',
    'profile.intro.stop': 'Stopp',
    'profile.intro.listen': 'Audio-Vorstellung anhören',
    'mood.noneSelected': 'Kein Mood ausgewählt',
    'mood.today': 'Heute',
    'mood.changeHint': 'Tippe, um deine Stimmung zu ändern.',
    'mood.selectHint': 'Tippe, um deine Stimmung des Tages zu wählen.',
    'mood.change': 'Ändern',
    'mood.select': 'Wählen',
    'settings.logout': 'Abmelden',
    'settings.deleteAccount': 'Konto löschen',
    // Settings (Vollständigkeit)
    'settings.privacySection': 'Privatsphäre',
    'settings.whoCanSee': 'Wer kann mein Profil sehen?',
    'settings.localDataNote':
        'Deine Daten werden nur lokal auf diesem Gerät gespeichert. Es '
        'werden keine unnötigen Berechtigungen angefordert.',
    'settings.communitySafety': 'Community & Sicherheit',
    'settings.communityRules': 'Community Regeln',
    'settings.communityRulesSub': 'Respektvoller Umgang & Verhaltensregeln',
    'settings.passkeyCreate': 'Passkey erstellen',
    'settings.passkeyCreateSub':
        'Biometrischer Login (FaceID/TouchID) ohne Passwort',
    'settings.passkeyCreated': 'Passkey wurde erstellt.',
    'settings.passkeyFailed': 'Passkey-Erstellung fehlgeschlagen.',
    'settings.devices': 'Angemeldete Geräte',
    'settings.devicesSub': 'Wo bin ich eingeloggt? Überall abmelden',
    'devices.title': 'Angemeldete Geräte',
    'devices.logoutTitle': 'Überall abmelden?',
    'devices.logoutBody':
        'Du wirst auf allen anderen Geräten abgemeldet. Die Sitzung auf '
        'diesem Gerät bleibt bestehen. Die anderen Geräte müssen sich '
        'danach neu anmelden.',
    'devices.logoutBtn': 'Überall abmelden',
    'devices.logoutDone': 'Alle anderen Geräte wurden abgemeldet.',
    'devices.logoutFailed':
        'Abmelden ist fehlgeschlagen. Bitte prüfe deine Verbindung und '
        'versuche es erneut.',
    'devices.retry': 'Erneut versuchen',
    'devices.hint':
        'Hier siehst du, auf welchen Geräten du aktuell angemeldet bist. '
        'Über "Überall abmelden" beendest du alle anderen Sitzungen. '
        'Dieses Gerät bleibt angemeldet.',
    'devices.current': 'Dieses Gerät',
    'devices.activeNow': 'gerade aktiv',
    'devices.activeMinutesA': 'aktiv vor',
    'devices.activeMinutesB': 'Min.',
    'devices.activeHoursA': 'aktiv vor',
    'devices.activeHoursB': 'Std.',
    'devices.activeLastSeen': 'zuletzt aktiv am',
    'devices.empty':
        'Keine weiteren Geräte registriert. Öffne Wisp auf einem anderen '
        'Gerät (mindestens diese Version), damit es sich in der Liste zeigt.',
    'devices.signingOut': 'Melde ab …',
    'devices.logoutBtnLong': 'Überall abmelden (außer diesem Gerät)',
    'devices.logoutNote':
        'Die anderen Geräte werden sofort abgemeldet und müssen sich beim '
        'nächsten Öffnen neu einloggen.',
    'profile.title': 'Mein Profil',
    'profile.qrTooltip': 'Mein QR Code',
    'profile.unknown': 'Unbekannt',
    'profile.years': 'Jahre',
    'profile.ageUnknown': 'Alter unbekannt',
    'profile.typePrefix': 'Typ',
    'profile.aboutMe': 'Über mich',
    'profile.noBio': 'Noch keine Bio.',
    'profile.interests': 'Interessen',
    'profile.blindModeTitle': 'Persönlichkeit vor Aussehen',
    'profile.blindModeSub': 'Fotos erst nach Funke anzeigen',
    'profile.profileBtn': 'Profil',
    'profile.bugReportBtn': 'Bug melden',
    'profile.edit.title': 'Profil bearbeiten',
    'profile.edit.name': 'Name',
    'profile.edit.birthDate': 'Geburtsdatum',
    'profile.edit.birthDateHint': 'TT. MM. JJJJ',
    'profile.edit.birthDatePick': 'Bitte auswählen',
    'profile.edit.birthDateHelp': 'Wähle dein Geburtsdatum',
    'profile.edit.gender': 'Geschlecht',
    'profile.edit.lookingFor': 'Ich suche',
    'profile.edit.relationship': 'Was suchst du?',
    'profile.edit.location': 'Standort',
    'profile.edit.city': 'Ort / Stadt',
    'profile.edit.cityHint': 'z. B. Berlin',
    'profile.edit.gpsTooltip': 'Standort erkennen (GPS)',
    'profile.edit.country': 'Land',
    'profile.edit.state': 'Bundesland',
    'profile.edit.stateHint': 'Bitte wählen',
    'profile.edit.stateNotApplicable':
        'Bundesland entfällt außerhalb Deutschlands.',
    'profile.edit.rel.casual': 'Lockere Bekanntschaft',
    'profile.edit.rel.dating': 'Ernsthaftes Dating',
    'profile.edit.rel.relationship': 'Feste Beziehung',
    'profile.edit.rel.friends': 'Freundschaft',
    'profile.edit.rel.open': 'Offen für alles',
    'profile.edit.minAgeLabel': 'Mindestalter',
    'profile.edit.maxAgeLabel': 'Höchstalter',
    'common.years': 'Jahre',
    'onb.page1.title': 'Privatsphäre & Darstellung',
    'onb.page2.title': 'Dein Profil',
    'onb.page3.title': 'Fertig',
    'onb.next': 'Weiter',
    'onb.back': 'Zurück',
    'onb.finish': 'Fertig werden',
    'chat.hint': 'Nachricht...',
    'chat.send': 'Senden',
    'chat.empty': 'Schreib die erste Nachricht! 😊',
    'chat.photosUnlocked': '🔓 Fotos wurden freigeschaltet',
    'chat.report': 'Bild melden',
    'chat.block': 'Nutzer blockieren',
    'chat.blockSub':
        'Keine Nachrichten, Likes oder Funken mehr von dieser Person.',
    'chat.end': 'Funke beenden',
    'chat.call': 'Audio Anruf',
    'chat.more': 'Weitere Optionen',
    'dh.event.startingSoon': 'Dating Hour startet gleich',
    'dh.event.cancelledToday':
        'Heute fällt die Dating Hour aus: Es haben sich nicht genug '
        'Personen angemeldet.',
    'dh.event.serverTimeWarn':
        'Die Server-Zeit konnte nicht verifiziert werden.',
    'dh.event.loadErrorFull': 'Fehler beim Laden: {error}',
    'dh.event.autoJoinFailed': 'Auto-Beitritt fehlgeschlagen: {error}',
    'dh.event.autoJoinAsk':
        'Das Event ist für heute vorbei. Möchtest du beim nächsten '
        'Mal automatisch dabei sein?',
    'dh.event.welcomeBack':
        'Willkommen zurück! Du bist automatisch wieder dabei.',

    'dh.rules.title': 'Dating Hour Regeln',
    'dh.rules.intro':
        'Bitte lies diese Regeln aufmerksam durch, bevor du teilnimmst.',
    'dh.rules.acceptedTitle': 'Regeln akzeptiert',
    'dh.rules.next': 'Weiter',
    'dh.how.title': 'Wie funktioniert Dating Hour?',
    'dh.how.intro':
        'Die Dating Hour läuft jeden Samstag von 20:00 bis 21:00 Uhr. '
        'Hier ist der Ablauf im Überblick:',
    'dh.how.next': 'Zur Dating Hour',
    'dh.rules.introLong':
        'Bitte lies diese Regeln aufmerksam durch, bevor du an der Dating '
        'Hour teilnimmst.',
    'dh.rules.bodyFun': 'Viel Spaß bei der Dating Hour!',
    'dh.rules.1.title': 'Respektvoll bleiben',
    'dh.rules.1.body':
        'Behandele deinen Gegenüber mit Respekt. Keine Beleidigungen, '
        'Diskriminierung oder unerwünschte Nachrichten.',
    'dh.rules.2.title': 'Keine persönlichen Daten teilen',
    'dh.rules.2.body':
        'Gib keine Adressen, Telefonnummern oder Kontodetails preis. '
        'Bleibt zunächst in der App.',
    'dh.rules.3.title': 'Ehrliches Profil',
    'dh.rules.3.body':
        'Nutze nur echte Angaben und aktuelle Bilder. Fake Profile oder '
        'Identitätsdiebstahl werden gemeldet.',
    'dh.rules.4.title': '5 Minuten Regel',
    'dh.rules.4.body':
        'Jeder Chat dauert maximal 5 Minuten. Danach entscheidest du, ob '
        'du den Funken verlängern möchtest.',
    'dh.rules.5.title': 'Keine unerwünschten Bilder',
    'dh.rules.5.body':
        'Sende keine intimen Bilder oder unerwünschten Content. Verstöße '
        'führen zur sofortigen Sperrung.',
    'dh.rules.6.title': 'Minderjährigenschutz',
    'dh.rules.6.body':
        'Die Dating Hour ist erst ab 16 Jahren freigegeben. Jüngere '
        'Nutzer werden automatisch ausgeschlossen.',
    'dh.how.step1.title': 'Beitreten',
    'dh.how.step1.body':
        'Wähle deine Präferenzen und trete dem samstäglichen Event '
        'bei. Du kannst jederzeit wieder austreten.',
    'dh.how.step2.title': 'Warten auf eine Zuordnung',
    'dh.how.step2.body':
        'Die App verbindet dich mit einer passenden Person. Sobald beide '
        'bereit sind, startet der 5 Minuten Chat.',
    'dh.how.step3.title': '5 Minuten chatten',
    'dh.how.step3.body':
        'Lerne die Person in einem kurzen, zeitlich begrenzten Gespräch '
        'kennen. Fotos werden je nach Einstellung angezeigt.',
    'dh.how.step4.title': 'Entscheidung',
    'dh.how.step4.body':
        'Nach dem Gespräch entscheidest du, ob du den Kontakt verlängern '
        'möchtest.',
    'dh.how.step5.title': 'Funken',
    'dh.how.step5.body':
        'Wenn beide sich für eine Verlängerung entscheiden, entsteht ein '
        'Funke und ihr könnt weiter chatten.',
    'dh.chat.sparkJumped': 'Ein Funke ist übersprungen! Chat wird geöffnet...',
    'dh.chat.noSpark': 'Kein Funke',
    'dh.chat.keepSearching': 'Weiter suchen',
    'dh.chat.e2e': 'Ende zu Ende verschlüsselt',
    'dh.chat.leaveTitle': 'Chat verlassen?',
    'dh.chat.leaveBody':
        'Wenn du den Chat verlässt, gilt das als "Ablehnen". Möchtest du '
        'wirklich gehen?',
    'dh.chat.stay': 'Bleiben',
    'dh.chat.leaveDecline': 'Verlassen & Ablehnen',
    'dh.chat.sayHello': 'Sag hallo zu {name}!',
    'dh.chat.fiveMinutes':
        'Ihr habt 5 Minuten Zeit, euch kennenzulernen. Danach entscheidet '
        'ihr beide: Funke oder weitersuchen?',
    'dh.chat.icebreakerBtn': 'Gesprächsstarter senden',
    'dh.chat.hint': 'Nachricht...',
    'dh.chat.timeUp':
        'Die 5 Minuten sind um!\nMöchtest du euch wiedersehen?',
    'dh.chat.decline': 'Ablehnen',
    'dh.chat.accept': 'Annehmen',
    'dh.chat.bothMustAccept':
        'Beide müssen "Annehmen" drücken für einen Funken.',
    'dh.chat.voted': 'Du hast abgestimmt. Warte auf deine Gegenseite...',
    'dh.chat.resultPending':
        'Sobald beide entschieden haben, erfährst du das Ergebnis.',
    'dh.chat.backToOverview': 'Zurück zur Übersicht',
    'dh.chat.sendFailed': 'Nachricht konnte nicht gesendet werden.',
    'dh.prefs.title': 'Dating Hour: Präferenzen',
    'dh.prefs.header': 'Deine Dating Hour Präferenzen',
    'dh.prefs.headerSub':
        'Diese Einstellungen helfen uns, dich mit passenden Personen zu '
        'verbinden. Du kannst sie vor jedem Event anpassen.',
    'dh.prefs.ageRange': '{min} bis {max} Jahre',
    'dh.prefs.sectionJoin': 'Teilnahme',
    'dh.prefs.autoJoin': 'Automatisch wieder dabei sein',
    'dh.prefs.autoJoinSub':
        'Wenn aktiviert, nimmst du am nächsten Dating Hour Event '
        'automatisch teil.',
    'dh.prefs.traitHint':
        'Wähle eine Eigenschaft oder gib deine eigene ein. Dies fließt '
        'als weicher Faktor bei den Funken-Vorschlägen ein.',
    'dh.prefs.traitHintField':
        'z. B. "Gute Laune", "Tiefgründige Gespräche"...',
    'dh.prefs.habits': 'Gewohnheiten (optional)',
    'dh.prefs.habitsSub':
        'Personen mit passenden Gewohnheiten werden dir bei den '
        'Funken-Vorschlägen zuerst vorgeschlagen, ausgeschlossen wird niemand.',
    'dh.prefs.save': 'Präferenzen speichern',
    'dh.prefs.saveNote':
        'Speichern meldet dich NICHT an. Deine Teilnahme bestätigst du '
        'separat mit "Ich bin dabei" auf dem Event-Screen.',
    'dh.prefs.saved':
        'Präferenzen gespeichert. Deine Teilnahme meldest du über "Ich '
        'bin dabei" am Event-Tag an.',
    'dh.event.joinConfirmTitle': 'Am Event teilnehmen?',
    'dh.event.join': 'Ich bin dabei',
    'dh.event.joined': 'Du nimmst am Dating Hour Event teil!',
    'dh.event.left': 'Du hast das Event verlassen.',
    'dh.event.bye': 'Bis zum nächsten Mal!',
    'dh.event.noThanks': 'Nein, danke',
    'dh.event.yesPlease': 'Ja, gerne',
    'dh.event.title': 'Dating Hour',
    'dh.event.ended': 'Datinghour beendet',
    'dh.event.joinNow': 'Jetzt beitreten & chatten',
    'dh.event.leave': 'Raus',
    'dh.event.setPrefs': 'Präferenzen festlegen',
    'dh.event.nextIn': 'Nächstes Event in {d}',
    'dh.event.searching': 'Suche läuft...',
    'dh.event.loadError': 'Fehler beim Laden',
    'dh.event.searchingPartner': 'Wir suchen gerade einen Partner...',
    'dh.event.toChat': 'Zum Chat',
    'dh.event.nonePlanned': 'Aktuell ist kein Dating Hour Event geplant.',
    'dh.event.remaining': 'Noch {d}',
    'dh.event.startIn': 'Start in {d}',
    'dh.event.chatsRunning': 'Chats laufen.',
    'dh.event.waitStart': 'Warte auf den Start.',
    'dh.event.participating': 'Du nimmst teil!',

    'profile.edit.filters': 'Filter & Präferenzen',
    'profile.edit.radiusMode': 'Suchradius definieren über',
    'profile.edit.maxDistance': 'Maximale Entfernung: {km} km',
    'profile.edit.minAge': 'Mindestalter: {age} Jahre',
    'profile.edit.maxAge': 'Höchstalter: {age} Jahre',
    'profile.edit.bio': 'Bio',
    'profile.edit.music': 'Musik',
    'profile.edit.musicSub':
        'Welche Musik beschreibt dich? Dein Geschmack fließt in den '
        'Verbindungs-Score ein.',
    'profile.edit.habits': 'Gewohnheiten',
    'profile.edit.habitsSub':
        'Wie stehst du dazu? Diese Angaben beeinflussen, wen du bei '
        '"Find your Match" siehst. Es werden nur Personen gezeigt, die '
        'maximal so viel konsumieren wie du.',
    'profile.edit.interests': 'Interessen',
    'profile.edit.personality': 'Persönlichkeitstest',
    'profile.edit.personalityDone':
        'Du hast den Test abgeschlossen. Du kannst ihn jederzeit '
        'wiederholen.',
    'profile.edit.personalityOpen': 'Zeig anderen, wer du wirklich bist.',
    'profile.edit.personalityRetake': 'Test wiederholen',
    'profile.edit.personalityStart': 'Persönlichkeitstest starten',
    'profile.edit.saved': 'Profil gespeichert',
    'profile.edit.savedNoSync':
        'Lokal gespeichert. Server-Sync fehlgeschlagen, bitte später '
        'erneut speichern.',
    'profile.edit.missingFields':
        'Es fehlen noch Angaben oder einige Felder sind fehlerhaft (rot '
        'markiert).',
    'profile.edit.missingFieldsHint':
        'Es fehlen noch Angaben oder einige Felder sind fehlerhaft (rot '
        'markiert). Bitte prüfe das Formular.',
    'profile.edit.birthDateMissing': 'Bitte wähle dein Geburtsdatum',
    'profile.edit.photoUpdated': 'Profilbild aktualisiert.',
    'profile.edit.photoUploadError': 'Fehler beim Hochladen: {error}',
    'profile.edit.photoPolicyBlocked':
        'Dieses Bild entspricht nicht unseren Richtlinien und wurde nicht '
        'hochgeladen.',
    'profile.edit.photoNsfwTitle': 'Bild nicht freigegeben',
    'profile.edit.photoNsfwBody':
        'Dieses Bild wurde lokal auf deinem Gerät als potenziell '
        'anstößig eingestuft und wird nicht hochgeladen.',
    'profile.edit.photoNsfwChoice': 'Was möchtest du tun?',
    'profile.edit.photoNsfwAppeal': 'Einspruch einlegen',
    'profile.edit.photoNsfwUnderstood': 'Verstanden',
    'profile.edit.photoNsfwVerdict': 'Lokaler Befund: {label} ({score} %).',
    'profile.edit.photoNsfwNotUploaded':
        'Das Bild wird nicht als Profilbild hochgeladen.',
    'profile.edit.photoOkTitle': 'Bild geprüft',
    'profile.edit.photoOkBody':
        'Dein Bild ist okay und kann verwendet werden.',
    'profile.edit.photoOkBtn': 'Weiter',
    'profile.edit.appealSubmitted':
        'Einspruch eingereicht. Wir benachrichtigen dich über das Ergebnis.',
    'profile.edit.appealFailed':
        'Einspruch konnte nicht eingereicht werden. Bitte später erneut.',
    'profile.appeal.approvedTitle': 'Bild freigegeben',
    'profile.appeal.approvedBody':
        'Dein Einspruch wurde geprüft: Das Bild ist freigegeben. Möchtest '
        'du es jetzt als Profilbild verwenden?',
    'profile.appeal.useBtn': 'Jetzt verwenden',
    'profile.appeal.applied': 'Profilbild übernommen.',
    'profile.appeal.rejectedTitle': 'Bild abgelehnt',
    'profile.appeal.rejectedBody':
        'Dein Einspruch wurde geprüft: Das Bild wurde abgelehnt und kann '
        'nicht verwendet werden. Wähle bitte ein anderes Profilbild.',
    'profile.appeal.okBtn': 'Verstanden',
    'profile.edit.photoNsfwOther': 'Anderes Bild wählen',
    'profile.edit.locationDetected': 'Standort erkannt und übernommen.',
    'profile.edit.locationFailed':
        'Standort konnte nicht ermittelt werden. Bitte gib ihn manuell '
        'ein oder erlaube den Zugriff.',
    'profile.edit.locationSuspicious':
        'Hinweis: Dieser Standort weicht deutlich von deinen bisherigen '
        'Standorten auf diesem Gerät ab.',
    'profile.edit.locationError': 'Fehler bei der Standortermittlung: {error}',
    'profile.edit.unsavedTitle': 'Ungespeicherte Änderungen',
    'profile.edit.unsavedBody':
        'Deine Profiländerungen wurden noch nicht gespeichert. Was '
        'möchtest du tun?',
    'profile.edit.unsavedDiscard': 'Verwerfen',
    'profile.detail.aboutMe': 'Über mich',
    'profile.detail.noBio': 'Noch keine Bio.',
    'profile.detail.interests': 'Interessen',
    'profile.detail.commonWithYou': 'Gemeinsam mit dir',
    'profile.detail.more': 'Weitere',
    'profile.detail.music': 'Musik',
    'profile.detail.sameTaste': 'Gleicher Geschmack',
    'profile.detail.noMusic': 'Kein Musik-Geschmack angegeben.',
    'common.refresh': 'Aktualisieren',
    'settings.twoFactor': 'Zwei-Faktor-Schutz (2FA)',
    'settings.twoFactorActive': 'Aktiv: Login nur mit Authenticator-Code',
    'settings.twoFactorSetup':
        'Login zusätzlich mit Authenticator-App sichern',
    'settings.notifyLikesSub': 'Wenn dich jemand liked',
    'settings.notifyMessagesSub': 'Wenn dir jemand schreibt',
    'settings.unifiedPush': 'Push ohne Google (UnifiedPush)',
    'settings.unifiedPushOn': 'Aktiv - Endpunkt ist hinterlegt.',
    'settings.unifiedPushOff':
        'Benötigt eine Distributor-App wie ntfy (F-Droid). FCM bleibt in '
        'der Play-Variante aktiv.',
    'settings.blurSub':
        'Schutz vor unangemessenen Inhalten: Bilder deiner Gegenstelle '
        'werden erst nach Bestätigung gezeigt (lang drücken zum Melden).',
    'settings.keyBackup': 'Verschlüsseltes Key-Backup',
    'settings.keyBackupSub':
        'Sichert die private Identität deiner Ende-zu-Ende-Verschlüsselung '
        '(passwortverschlüsselt, AES-256-GCM). Nur damit kannst du nach '
        'Gerätewechsel wieder verschlüsselt chatten. Verlust von Backup '
        'UND Passwort ist unwiederbringlich.',
    'settings.backupCreateSub': 'Erzeugt einen verschlüsselten Code',
    'settings.backupRestoreSub': 'Überschreibt die aktuelle E2E-Identität',
    'settings.safetyCenter': 'Safety Center',
    'settings.safetyCenterSub':
        'Hilfe bei Belästigung oder Stalking, Blockieren, Melden',
    // Datenschutz & Account
    'privacy.title': 'Datenschutz & Account',
    'privacy.yourData': 'Deine Daten',
    'privacy.dataInfo':
        'Wisp speichert Profilinformationen, Standortdaten (nur wenn du '
        'sie freigibst), Fotos, Chats, Likes und Funken. Alle Daten '
        'werden verschlüsselt übertragen und nur so lange gespeichert, '
        'wie dein Account aktiv ist.',
    'privacy.export': 'Meine Daten exportieren',
    'privacy.exportSub': 'JSON Download aller personenbezogenen Daten',
    'privacy.exportFailed': 'Export fehlgeschlagen',
    'privacy.import': 'Daten importieren',
    'privacy.importSub': 'JSON-Datenexport wiederherstellen',
    'privacy.importTitle': 'Daten importieren',
    'privacy.importBody':
        'Füge hier den Inhalt deiner Export-Datei (wisp_data_export.json) '
        'ein. Profil, Einstellungen und Präferenzen werden '
        'wiederhergestellt.',
    'privacy.importHint': '{ ... JSON hier einfügen ... }',
    'privacy.importApply': 'Importieren',
    'privacy.importInvalid': 'Das eingefügte JSON konnte nicht gelesen '
        'werden. Bitte prüfe den Inhalt.',
    'privacy.importDone': 'Daten erfolgreich importiert.',
    'privacy.importFailed': 'Import fehlgeschlagen',
    'privacy.accountSection': 'Anmeldung',
    'privacy.accountInfo':
        'E-Mail- und Passwort-Änderungen erfordern dein aktuelles '
        'Passwort. Bei E-Mail-Wechsel bestätigst du die neue Adresse '
        'über einen Link in beiden Postfächern.',
    'privacy.changeEmail': 'E-Mail-Adresse ändern',
    'privacy.changeEmailInfo':
        'Du erhältst einen Bestätigungs-Link an deine alte UND neue '
        'Adresse. Die Änderung wird erst nach Bestätigung aktiv.',
    'privacy.changeEmailSent':
        'Bestätigungs-Link an beide E-Mail-Adressen gesendet.',
    'privacy.changePassword': 'Passwort ändern',
    'privacy.changePasswordDone': 'Passwort geändert.',
    'privacy.changeFailed': 'Änderung fehlgeschlagen',
    'auth.passwordCurrent': 'Aktuelles Passwort',
    'auth.passwordNew': 'Neues Passwort',
    'auth.passwordConfirm': 'Neues Passwort wiederholen',
    'privacy.processors': 'Auftragsverarbeiter',
    'privacy.processorsInfo':
        'Folgende Dienstleister (Art. 28 DSGVO) verarbeiten Daten im '
        'Auftrag. Chat-Inhalte sind Ende-zu-Ende-verschlüsselt und werden '
        'von keinem Dienstleister verarbeitet.',
    'privacy.processorSupabase': 'Hosting, Datenbank, Authentifizierung (EU)',
    'privacy.processorGoogle': 'Push-Benachrichtigungen',
    'privacy.processorBrevo': 'Transaktions-E-Mails (Bestätigung, Reset)',
    'privacy.processorCloudflare': 'CAPTCHA (Turnstile) und TURN-Relay',
    'privacy.processorNetlify': 'Hosting der Anmelde-/CAPTCHA-Seite',
    'privacy.processorApple': 'App-Store-Verteilung',
    'privacy.consent': 'Einwilligungen',
    'privacy.location': 'Standortfreigabe',
    'privacy.locationSub':
        'Du kannst die Standortfreigabe in den Systemeinstellungen deines '
        'Geräts jederzeit widerrufen.',
    'privacy.openLocationSettings': 'Standort-Einstellungen öffnen',
    'privacy.push': 'Push Benachrichtigungen',
    'privacy.pushSub':
        'Öffnet die App-Einstellungen deines Geräts, dort kannst du die '
        'Benachrichtigungen steuern.',
    'privacy.openAppSettings': 'App-Einstellungen öffnen',
    'privacy.dangerZone': 'Gefahrenzone',
    'privacy.deleteAccount': 'Account dauerhaft löschen',
    'privacy.deleteAccountSub':
        'DSGVO Art. 17: Recht auf Löschung. Alle Daten werden entfernt.',
    'privacy.deleteTitle': 'Account löschen?',
    'privacy.deleteBody':
        'Dieser Schritt kann nicht rückgängig gemacht werden. Alle deine '
        'Daten (Profil, Fotos, Chats, Funken, Likes) werden dauerhaft '
        'gelöscht.',
    'privacy.deleteConfirm': 'Endgültig löschen',
    'privacy.deleteFailed': 'Account konnte nicht gelöscht werden',
    'common.save': 'Speichern',
    'common.cancel': 'Abbrechen',
    'common.ok': 'OK',
    'common.yes': 'Ja',
    'common.no': 'Nein',
    'common.continue': 'Weiter',
    'common.back': 'Zurück',
    'common.loading': 'Lädt…',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email oder Passwort ist falsch.',
    'error.notConfirmed': 'Bitte bestätige zuerst deine Emailadresse.',
    'error.alreadyRegistered':
        'Diese Emailadresse ist bereits registriert. Bitte melde dich '
        'direkt an oder setze dein Passwort zurück.',
    'error.rateLimited': 'Zu viele Anfragen in kurzer Zeit. Bitte warte '
        'einen Moment und versuche es erneut.',
    'error.weakPassword': 'Das Passwort ist zu schwach. Bitte wähle ein '
        'längeres Passwort mit Groß-/Kleinbuchstaben, Zahlen und '
        'Sonderzeichen.',
    'error.captchaRejected': 'Der Sicherheitscheck wurde vom Server '
        'abgelehnt. Bitte versuche es erneut.',
    'error.signupFailed': 'Registrierung auf dem Server fehlgeschlagen. '
        'Bitte versuche es später erneut.',
    'error.loginFailed': 'Anmeldung fehlgeschlagen. Bitte versuche es '
        'erneut.',
    'error.generic': 'Etwas ist schiefgelaufen. Bitte versuche es erneut.',
  },
  'en': {
    'auth.login': 'Log in',
    'auth.register': 'Sign up',
    'auth.name': 'Name',
    'auth.email': 'Email',
    'auth.password': 'Password',
    'auth.passwordHint': 'At least 8 characters',
    'auth.forgot': 'Forgot password?',
    'auth.keepLoggedIn': 'Stay logged in',
    'auth.keepLoggedInSub':
        'Stay automatically logged in when you close the app (recommended).',
    'auth.toRegister': 'No account yet? Sign up',
    'auth.toLogin': 'Already have an account? Log in',
    'auth.passkey': 'Sign in with Passkey',
    'auth.passkeyCreate': 'Create Passkey',
    'auth.captcha': 'Security check',
    'auth.registerTitle': 'Create account',
    'auth.welcomeBack': 'Welcome back',
    'auth.birthDate': 'Date of birth',
    'auth.birthDateHint': 'DD MM YYYY',
    'auth.birthDatePick': 'Please select',
    'auth.birthDateMissing': 'Please choose your date of birth.',
    'auth.gender': 'Gender',
    'gender.male': 'Male',
    'gender.maleTrans': 'Male (F to M)',
    'gender.female': 'Female',
    'gender.femaleTrans': 'Female (M to F)',
    'gender.diverse': 'Diverse',
    'gender.other': 'Own / Other',
    'auth.passwordHintStrong': 'At least 8 characters, with upper and lower '
        'case letters, a number and a special character',
    'auth.showPassword': 'Show password',
    'auth.hidePassword': 'Hide password',
    'auth.captchaRegister': 'Please complete the security check to sign up.',
    'auth.captchaLogin': 'Please complete the security check to log in.',
    'captcha.retry': 'Try again',
    'language.german': 'German',
    'language.english': 'English',
    'nav.home': 'Home',
    'nav.discover': 'Discover',
    'nav.interests': 'Interests',
    'nav.profile': 'Profile',
    'settings.title': 'Settings',
    'settings.appearance': 'Appearance',
    'settings.system': 'System',
    'settings.light': 'Light',
    'settings.dark': 'Dark',
    'settings.colors': 'Color scheme',
    'settings.language': 'Language',
    'settings.notifications': 'Notifications',
    'settings.push': 'Push notifications',
    'settings.pushEnable': 'Enable notifications',
    'settings.pushEnableSub': 'Messages, likes, sparks and event reminders',
    'settings.notifyMessages': 'Chat messages',
    'settings.notifyLikes': 'New likes',
    'settings.notifyFunken': 'New sparks',
    'settings.notifyFunkenSub': 'When a spark is created',
    'settings.notifyDatingHour': 'Dating Hour reminder',
    'settings.notifyDatingHourSub': '10 minutes before start, if joined',
    'settings.chatSafety': 'Chat safety',
    'settings.blur': 'Show pictures pixelated',
    'settings.e2e': 'E2E identity',
    'settings.backupCreate': 'Create backup',
    'settings.backupRestore': 'Restore backup',
    'settings.passkeyDiagnose': 'Passkey diagnostics',
    'settings.privacyAccount': 'Privacy & account',
    'settings.privacyAccountSub': 'Stored data, consents, delete account',
    'settings.pause': 'Pause profile',
    'settings.pauseSub':
        'Invisible in Discovery and Find your Match. Sparks and chats '
        'remain.',
    'settings.pauseActive':
        'Profile is paused and invisible to new people.',
    'settings.pauseConfirmTitle': 'Pause profile?',
    'settings.pauseConfirmBody':
        'Your profile will no longer appear in Discovery and Find your '
        'Match. Existing sparks and chats remain. You can end the pause '
        'at any time.',
    'settings.pauseConfirmBtn': 'Pause',
    'settings.pauseOn':
        'Profile paused. You are invisible until you end the pause.',
    'settings.pauseOff': 'Pause ended. Your profile is visible again.',
    'settings.visEveryoneSub':
        'Your profile appears in Discovery and Find your Match.',
    'settings.visMatchesSub':
        'Only people you have a spark with can see your profile.',
    'settings.visHiddenSub':
        'Pause mode: invisible to all new people. Sparks and chats remain.',
    'settings.visEveryone': 'Everyone',
    'settings.visMatchesOnly': 'Sparks only',
    'settings.visHidden': 'Invisible (paused)',
    'mood.happy': 'Happy',
    'mood.relaxed': 'Relaxed',
    'mood.adventurous': 'Adventurous',
    'mood.flirty': 'Flirty',
    'mood.thoughtful': 'Thoughtful',
    'mood.tired': 'Tired',
    'theme.classic': 'Classic WispDating',
    'theme.ocean': 'Ocean',
    'theme.forest': 'Forest',
    'theme.sunset': 'Sunset',
    'theme.lavender': 'Lavender',
    'theme.slate': 'Slate',
    'theme.colorScheme': 'Color scheme',
    'dm.discovery': 'Discover',
    'dm.discoveryDesc': 'Browse profiles, send sparks, chat',
    'dm.findMatch': 'Find your Match',
    'dm.findMatchDesc': 'Listen to or read the intro, then decide',
    'dm.randomChat': 'Random chat',
    'dm.randomChatDesc': 'Direct text chat with a randomly matched person',
    'dm.qrScan': 'Scan QR code',
    'dm.qrScanDesc': "Scan someone's code and connect instantly",
    'dm.datingHour': 'Dating Hour (event)',
    'dm.datingHourDesc':
        'Saturdays 8 to 9 pm: 5-minute chats with a decision phase',
    'dm.transitSpark': 'Transit Spark',
    'dm.transitSparkDesc':
        'Exchanged glances but too shy? Spark later - even after you have '
        'both moved on.',
    'dm.groupMeet': 'Meet people',
    'dm.groupDirect': 'Connect directly',
    'dm.groupOnTheGo': 'On the go',
    'dm.pickHint': 'Choose a mode to discover new people:',
    'common.new': 'NEW',
    'transit.title': 'Transit Spark',
    'transit.start': 'Activate radar',
    'transit.stop': 'Stop radar',
    'transit.active': 'Radar active - visible to nearby Wisp devices.',
    'transit.inactive': 'Radar off. Activate it when you are on the go.',
    'transit.remaining': 'Active for another {time}',
    'transit.seenCount': 'Seen {count} Wisp devices in range.',
    'transit.exchanged': 'Exchanged glances',
    'transit.modeLabel': 'Where are you?',
    'transit.mode.transit': 'Train / café',
    'transit.mode.convention': 'Convention / event',
    'transit.modeHint':
        'Convention mode: only strong signals count (real sight contact '
        'in dense environments).',
    'transit.sheetTitle': 'Who was it?',
    'transit.sheetHint':
        'Pick 1-3 traits you noticed about the person - your selection '
        'sharpens the matching.',
    'transit.sheetSend': 'Spark',
    'transit.tag.black_hoodie': 'Black hoodie',
    'transit.tag.jacket': 'Jacket',
    'transit.tag.cap': 'Cap',
    'transit.tag.glasses': 'Glasses',
    'transit.tag.headphones': 'Headphones',
    'transit.tag.backpack': 'Backpack',
    'transit.tag.tote_bag': 'Tote bag',
    'transit.tag.lanyard': 'Lanyard / badge',
    'transit.tag.scarf': 'Scarf',
    'transit.tag.colorful_top': 'Colorful top',
    'transit.stored':
        'Signal stored. If the other person feels the same moment and '
        'signals too, you will match.',
    'transit.matchTitle': 'Spark jumped over!',
    'transit.matchBody':
        'The other person felt the same moment. Check your sparks - you '
        'can chat now.',
    'transit.later': 'Later',
    'transit.openSparks': 'To the sparks',
    'transit.startFailed':
        'Radar could not start. Turn on Bluetooth and grant permission.',
    'transit.sendFailed': 'Signal could not be sent. Please try again.',
    'transit.howTitle': 'How does it work?',
    'transit.howBody':
        'Activate the radar while you are on the go (train, café, '
        'convention). Your device exchanges anonymous, random tokens with '
        'other Wisp devices nearby - no names, no location, no photos. '
        'Later, tap "Exchanged glances": if the other person feels the '
        'same moment and signals too, a spark is created.',
    'transit.privacyNote':
        'Tokens are random, rotate regularly and expire after 45 minutes. '
        'Only what you actively send is stored - nothing leaves your '
        'device unless you choose to signal.',
    'transit.teenNote':
        'Under 18? You only see age-compatible users - enforced '
        'server-side.',
    'onboarding.appbarTitle': 'Nice to meet you',
    'onboarding.skipAll': 'Skip',
    'onboarding.fillLater': 'Fill in later',
    'onboarding.next': 'Continue',
    'onboarding.hello.title': 'Hi, I am Wisp!',
    'onboarding.hello.body':
        'Over the next few minutes we will set up your profile - as a '
        'short conversation instead of a form. Everything is skippable, '
        'nothing is wrong.',
    'onboarding.blind.title': 'Personality before looks',
    'onboarding.blind.body':
        'By default you will see only name, age, bio and interests '
        'first - no photos. Decide with your head, not just your eyes. '
        'Switchable at any time.',
    'onboarding.connections.title': 'Real connections',
    'onboarding.connections.body':
        'A spark is created only if you both choose each other. Photos '
        'unlock then and you can start chatting - fair instead of '
        'superficial.',
    'onboarding.q.bio':
        'What makes you you? Tell me a little about yourself - what '
        'you love, what moves you, what you find funny.',
    'onboarding.q.bioHint': 'A few honest sentences are plenty …',
    'onboarding.q.interests':
        'What do you like spending time on? Pick a few interests - '
        'they will later become shared topics and sparks.',
    'onboarding.q.photo':
        'Would you like to show a profile picture? No pressure - '
        'photos are only visible after a spark anyway.',
    'onboarding.photoLater': 'You can upload a profile picture later.',
    'onboarding.q.habits':
        'And how do you feel about smoking, alcohol and the like? ',
    'onboarding.q.habitsHint':
        'These answers feed your matching: you will only see people '
        'who consume at most as much as you do.',
    'onboarding.done.title': 'Done - glad you are here!',
    'onboarding.done.body':
        'Your profile is set up. You can change everything later in '
        'the settings. Enjoy discovering!',
    'chathist.tileTitle': 'Save chat history locally',
    'chathist.mode.off': 'Off',
    'chathist.mode.cap200': 'On (200 messages)',
    'chathist.mode.all': 'On (full history)',
    'chathist.tileSubPrefix': 'Encrypted (AES-256) on this device.',
    'chathist.deleteHint': 'Disabling deletes the history.',
    'chathist.dialogTitle': 'Save chat history',
    'chathist.modeWord': 'Mode:',
    'chat.safetyNumber': 'Safety number',
    'chat.safetyNumberTooltip': 'Safety number (E2E verification)',
    'chat.safetyChangedTitle': 'Safety number has changed',
    'chat.safetyChangedBody':
        'The encryption key of your contact has changed. This can happen '
        'after a reinstall - or it may indicate that someone is trying to '
        'intercept the conversation.\n\nVerify the safety number through '
        'a second channel (e.g. a call or in person) before continuing.',
    'chat.safetyChangedCancel': 'Cancel',
    'chat.safetyChangedAccept': 'Verified: accept',
    'chat.reconnectStillFailing': 'Connection still failing.',
    'chat.imageSourcePrompt': 'Choose a source for the image to send.',
    'chat.identityVerifiedTitle': 'Identity verified',
    'chat.close': 'Close',
    'chat.coolSpark': 'Cool spark',
    'chat.coolSparkError': 'Could not cool the spark: {error}',
    'chat.coolSparkDone': 'Spark cooled - you will find it under "Settled sparks" again.',
    'chat.backToSparks': 'Back to sparks',
    'chat.closeImageHint': 'Close (the image can no longer be viewed afterwards)',
    'settings.backupChoosePw': 'Choose backup password',
    'settings.restoreConfirmTitle': 'Restore identity?',
    'settings.backupPasteCode': 'Paste backup code',
    'settings.restored': 'E2E identity restored.',
    'settings.codeInvalid': 'Invalid or expired code.',
    'settings.passkeyDeleteTitle': 'Delete passkey?',
    'settings.delete': 'Delete',
    'settings.passkeyDeleted': 'Passkey deleted.',
    'settings.deleteFailed': 'Deletion failed.',
    'dh.prefs.setBtn': 'Set preferences',
    'dh.nextEventIn': 'Next event in',
    'dh.searching': 'Searching...',
    'dh.feature.noPhotos': 'No photos, no bios, just 5 minutes of real conversation.',
    'dh.feature.e2eTitle': 'End-to-end encrypted',
    'dh.feature.e2eSub': 'Nobody but the two of you can read your messages (Signal protocol).',
    'dh.prefs.savedHint': 'Preferences saved. You join via "I am in" on the event day.',
    'report.detailsOptional': 'Additional details (optional)',
    'report.checkingTitle': 'Checking image…',
    'report.checkingSub': 'The AI is checking the reported image.',
    'report.retryLater': 'Please try again later.',
    'report.confirmed': 'Report confirmed',
    'report.forwardBtn': 'Forward for manual review',
    'report.forwardFailed': 'Forwarding failed. Please try again later.',
    'interests.likeWithdrawn': 'Like withdrawn.',
    'interests.likeWithdrawTooltip': 'Withdraw like',
    'interests.sparkConfirmBtn': 'Confirm spark',
    'interests.resparkDone': 'Spark with {name} is glowing again ✨',
    'interests.matchesSub': 'Confirmed mutual likes',
    'qr.openingChat': 'Opening chat with {name}...',
    'qr.enterFullCode': 'Please enter the full 8-digit code.',
    'qr.resolveFailed': 'Could not resolve the code.',
    'qr.shareSub': 'So others can find you',
    'qr.scanSub': 'Open the camera and scan a code',
    'qr.myCode': 'My QR code',
    'qr.yourCode': 'Your code',
    'qr.copyTooltip': 'Copy code',
    'qr.copied': 'Code copied to clipboard',
    'qr.shareHint': 'Share this code or the QR code with others. They can find you in the app and message you directly.',
    'meet.metTitle': 'Great that you met! 🎉',
    'meet.youWant': 'You want to meet',
    'meet.theyWant': '{name} would like to meet you',
    'meet.later': 'Maybe later',
    'meet.ideas': 'Ideas for a first meeting:',
    'home.settingsTooltip': 'Settings & privacy',
    'home.discoverSub': 'Get to know people through their intro.',
    'home.likesSub': 'Likes become sparks when you both like each other.',
    'random.partnerLeft': 'Your random chat partner has left.',
    'random.backToDiscover': 'Back to Discover',
    'random.connecting': 'Partner found! Connecting encrypted…',
    'profile.detail.unavailable': 'This profile is currently unavailable.',
    'safety.linkFailed': 'Could not open link.',
    'safety.protectOwnImages': 'Protect your own images',
    'safety.protectOwnImagesBody':
        'Images in incoming messages are blurred by default (settings - '
        'chat safety). Your own photos remain hidden until mutual quiz '
        'success.',
    'home.noMessages': 'No new messages',
    'home.noMessagesSub': 'New messages appear here once you have sparks.',
    'safety.sectionHelp': 'Immediate help',
    'safety.hotline1': 'Help hotline "Violence against women"',
    'safety.hotline1Sub': '116 016 - free, 24/7, anonymous',
    'safety.hotline2': 'Telephone counselling',
    'safety.hotline2Sub': '0800 111 0 111 - free, 24/7',
    'safety.hotline3': 'klicksafe (cyberbullying & counselling)',
    'safety.hotline3Sub': 'klicksafe.de',
    'safety.hotline4': 'Stalking helpline (Weisser Ring)',
    'safety.hotline4Sub': 'weisser-ring.de - 116 006',
    'safety.sectionProtect': 'Protection in WispDating',
    'safety.reportSomeone': 'Report someone',
    'safety.reportSomeoneBody':
        'In the chat via the flag icon at the top right, or by long-pressing '
        'an image. Your last messages are transparently submitted as context '
        'and personally reviewed by support.',
    'safety.blockSomeone': 'Block someone',
    'safety.blockSomeoneBody':
        'Chat menu (three dots) - Block. Likes and sparks are removed; '
        'future interactions are prevented server-side. The person is not '
        'notified.',
    'safety.stalkingGuide': 'Stalking guide',
    'safety.stalkingBody':
        'If someone is stalking you online (or offline): 1. Do not reply, '
        'deliberately end contact. 2. Document everything: screenshots with '
        'dates, chat history, profile names. 3. Block in the app and inform '
        'us via the report function. We can permanently suspend accounts. '
        '4. Change passwords and enable 2FA (settings). 5. If threatened or '
        'afraid: contact the police (110) or 116 006.',
    'safety.exportData': 'Export my data',
    'safety.exportDataSub': 'JSON export of all stored data',
    'spice.answerSent': 'Answer sent. Your partner will answer soon.',
    'spice.answerEdit': 'Edit answer',
    'spice.answer': 'Answer',
    'bugreport.sendFailed': 'Submission failed. Please try again later.',
    'home.noLikes': 'No new likes',
    'home.noSparks': 'No new sparks',
    'interests.sparksTitle': 'Sparks',
    'dh.feature.realChat': 'Real chat instead of profile check',
    'dh.info.title': 'How does Dating Hour work?',
    'dh.info.timeTitle': '5 minutes',
    'dh.info.timeSub': 'Then both decide: "Accept" or "Decline".',
    'dh.info.liveTitle': 'Live with real people',
    'dh.info.liveSub': 'You are connected live with another person who is also actively looking for a Dating Hour partner right now.',
    'dh.info.retryTitle': 'No spark? New chance!',
    'dh.info.retrySub': 'On "Decline" the algorithm immediately looks for someone new.',
    'chathist.off.title': 'Nothing (RAM only)',
    'chathist.cap200.title': '200 messages per chat',
    'chathist.all.title': 'Full history',
    'chathist.off.sub': 'Chats are gone after restart.',
    'chathist.cap200.sub': 'Encrypted, max. 200 per chat.',
    'chathist.all.sub': 'Encrypted, no limit.',
    'profile.menu.edit': 'Edit profile',
    'profile.menu.editSub': 'Change details, interests and intro',
    'profile.menu.preview': 'Profile preview',
    'profile.menu.previewSub': 'How others see you',
    'profile.menu.introPreview': 'Intro preview',
    'profile.menu.introPreviewSub': 'View your text and audio intro',
    'profile.preview.title': 'Profile preview',
    'profile.preview.hint': 'This is how other users see you (incl. age protection & blind mode):',
    'profile.preview.photoHidden': 'Your photos are not visible to others due to your settings (personality first / age protection).',
    'profile.preview.aboutMe': 'About me',
    'profile.preview.noBio': 'No bio yet.',
    'profile.preview.interests': 'Interests',
    'profile.preview.note': 'Note: Actual visibility depends on the age and settings of each viewer.',
    'profile.preview.type': 'Type',
    'profile.intro.title': 'My intro',
    'profile.intro.empty': 'You have not added a text intro yet.',
    'profile.intro.hint': 'Others get to know you through this intro before they see a photo. You can edit it under Edit profile.',
    'profile.intro.audioEmpty': 'No audio intro recorded yet.',
    'profile.intro.audioMissing': 'Audio intro not found.',
    'profile.intro.audioLoadError': 'Audio intro could not be loaded.',
    'profile.intro.stop': 'Stop',
    'profile.intro.listen': 'Listen to audio intro',
    'mood.noneSelected': 'No mood selected',
    'mood.today': 'Today',
    'mood.changeHint': 'Tap to change your mood.',
    'mood.selectHint': 'Tap to choose your mood of the day.',
    'mood.change': 'Change',
    'mood.select': 'Choose',
    'settings.logout': 'Log out',
    'settings.deleteAccount': 'Delete account',
    // Settings (Vollständigkeit)
    'settings.privacySection': 'Privacy',
    'settings.whoCanSee': 'Who can see my profile?',
    'settings.localDataNote':
        'Your data is stored only locally on this device. No unnecessary '
        'permissions are requested.',
    'settings.communitySafety': 'Community & safety',
    'settings.communityRules': 'Community rules',
    'settings.communityRulesSub': 'Respectful conduct & rules of behavior',
    'settings.passkeyCreate': 'Create passkey',
    'settings.passkeyCreateSub':
        'Biometric login (FaceID/TouchID) without a password',
    'settings.passkeyCreated': 'Passkey created.',
    'settings.passkeyFailed': 'Passkey creation failed.',
    'settings.devices': 'Signed-in devices',
    'settings.devicesSub': 'Where am I logged in? Sign out everywhere',
    'devices.title': 'Signed-in devices',
    'devices.logoutTitle': 'Sign out everywhere?',
    'devices.logoutBody':
        'You will be signed out on all other devices. The session on this '
        'device stays active. The other devices will need to sign in '
        'again afterwards.',
    'devices.logoutBtn': 'Sign out everywhere',
    'devices.logoutDone': 'All other devices have been signed out.',
    'devices.logoutFailed':
        'Signing out failed. Please check your connection and try again.',
    'devices.retry': 'Try again',
    'devices.hint':
        'Here you can see which devices are currently signed in. Use '
        '"Sign out everywhere" to end all other sessions. This device '
        'stays signed in.',
    'devices.current': 'This device',
    'devices.activeNow': 'active right now',
    'devices.activeMinutesA': 'active',
    'devices.activeMinutesB': 'min ago',
    'devices.activeHoursA': 'active',
    'devices.activeHoursB': 'h ago',
    'devices.activeLastSeen': 'last active on',
    'devices.empty':
        'No other devices registered. Open Wisp on another device (at '
        'least this version) so it shows up in the list.',
    'devices.signingOut': 'Signing out…',
    'devices.logoutBtnLong': 'Sign out everywhere (except this device)',
    'devices.logoutNote':
        'The other devices will be signed out immediately and must log in '
        'again the next time they open the app.',
    'profile.title': 'My profile',
    'profile.qrTooltip': 'My QR code',
    'profile.unknown': 'Unknown',
    'profile.years': 'years',
    'profile.ageUnknown': 'Age unknown',
    'profile.typePrefix': 'Type',
    'profile.aboutMe': 'About me',
    'profile.noBio': 'No bio yet.',
    'profile.interests': 'Interests',
    'profile.blindModeTitle': 'Personality over looks',
    'profile.blindModeSub': 'Show photos only after a spark',
    'profile.profileBtn': 'Profile',
    'profile.bugReportBtn': 'Report a bug',
    'profile.edit.title': 'Edit profile',
    'profile.edit.name': 'Name',
    'profile.edit.birthDate': 'Date of birth',
    'profile.edit.birthDateHint': 'DD. MM. YYYY',
    'profile.edit.birthDatePick': 'Please select',
    'profile.edit.birthDateHelp': 'Choose your date of birth',
    'profile.edit.gender': 'Gender',
    'profile.edit.lookingFor': 'I am looking for',
    'profile.edit.relationship': 'What are you looking for?',
    'profile.edit.location': 'Location',
    'profile.edit.city': 'City',
    'profile.edit.cityHint': 'e.g. Berlin',
    'profile.edit.gpsTooltip': 'Detect location (GPS)',
    'profile.edit.country': 'Country',
    'profile.edit.state': 'Federal state',
    'profile.edit.stateHint': 'Please select',
    'profile.edit.stateNotApplicable':
        'Federal state only applies within Germany.',
    'profile.edit.rel.casual': 'Casual acquaintance',
    'profile.edit.rel.dating': 'Serious dating',
    'profile.edit.rel.relationship': 'Committed relationship',
    'profile.edit.rel.friends': 'Friendship',
    'profile.edit.rel.open': 'Open to anything',
    'profile.edit.minAgeLabel': 'Minimum age',
    'profile.edit.maxAgeLabel': 'Maximum age',
    'common.years': 'years',
    'onb.page1.title': 'Privacy & appearance',
    'onb.page2.title': 'Your profile',
    'onb.page3.title': 'Done',
    'onb.next': 'Next',
    'onb.back': 'Back',
    'onb.finish': 'Finish',
    'chat.hint': 'Message...',
    'chat.send': 'Send',
    'chat.empty': 'Write the first message! 😊',
    'chat.photosUnlocked': '🔓 Photos were unlocked',
    'chat.report': 'Report image',
    'chat.block': 'Block user',
    'chat.blockSub':
        'No messages, likes or sparks from this person anymore.',
    'chat.end': 'End spark',
    'chat.call': 'Audio call',
    'chat.more': 'More options',
    'dh.event.startingSoon': 'Dating Hour starts soon',
    'dh.event.cancelledToday':
        "Today's Dating Hour is cancelled: not enough people signed up.",
    'dh.event.serverTimeWarn':
        'The server time could not be verified.',
    'dh.event.loadErrorFull': 'Loading failed: {error}',
    'dh.event.autoJoinFailed': 'Auto-join failed: {error}',
    'dh.event.autoJoinAsk':
        "Today's event is over. Would you like to automatically join "
        'the next one?',
    'dh.event.welcomeBack':
        'Welcome back! You are automatically in.',

    'dh.rules.title': 'Dating Hour rules',
    'dh.rules.intro':
        'Please read these rules carefully before joining.',
    'dh.rules.acceptedTitle': 'Rules accepted',
    'dh.rules.next': 'Next',
    'dh.how.title': 'How does Dating Hour work?',
    'dh.how.intro':
        'The Dating Hour takes place every Saturday from 20:00 to 21:00. '
        'Here is the flow at a glance:',
    'dh.how.next': 'Go to Dating Hour',
    'dh.rules.introLong':
        'Please read these rules carefully before taking part in the '
        'Dating Hour.',
    'dh.rules.bodyFun': 'Have fun at the Dating Hour!',
    'dh.rules.1.title': 'Stay respectful',
    'dh.rules.1.body':
        'Treat your counterpart with respect. No insults, discrimination '
        'or unwanted messages.',
    'dh.rules.2.title': 'No sharing of personal data',
    'dh.rules.2.body':
        'Do not share addresses, phone numbers or account details. Stay '
        'in the app for now.',
    'dh.rules.3.title': 'Honest profile',
    'dh.rules.3.body':
        'Use only real information and current pictures. Fake profiles '
        'or identity theft will be reported.',
    'dh.rules.4.title': '5 minute rule',
    'dh.rules.4.body':
        'Each chat lasts a maximum of 5 minutes. Afterwards you decide '
        'whether you want to extend the match.',
    'dh.rules.5.title': 'No unwanted pictures',
    'dh.rules.5.body':
        'Do not send intimate pictures or unwanted content. Violations '
        'lead to an immediate ban.',
    'dh.rules.6.title': 'Minor protection',
    'dh.rules.6.body':
        'The Dating Hour is only available from age 16. Younger users '
        'are automatically excluded.',
    'dh.how.step1.title': 'Join',
    'dh.how.step1.body':
        'Choose your preferences and join the Saturday event. You can '
        'leave at any time.',
    'dh.how.step2.title': 'Waiting for a match',
    'dh.how.step2.body':
        'The app connects you with a matching person. As soon as both '
        'are ready, the 5 minute chat starts.',
    'dh.how.step3.title': 'Chat for 5 minutes',
    'dh.how.step3.body':
        'Get to know the person in a short, time-limited conversation. '
        'Photos are shown depending on your settings.',
    'dh.how.step4.title': 'Decision',
    'dh.how.step4.body':
        'After the chat you decide whether you want to extend the '
        'contact.',
    'dh.how.step5.title': 'Sparks',
    'dh.how.step5.body':
        'If both decide to extend, a spark is created and you can keep '
        'chatting.',
    'dh.chat.sparkJumped': 'A spark jumped! Opening the chat...',
    'dh.chat.noSpark': 'No spark',
    'dh.chat.keepSearching': 'Keep searching',
    'dh.chat.e2e': 'End-to-end encrypted',
    'dh.chat.leaveTitle': 'Leave chat?',
    'dh.chat.leaveBody':
        'Leaving the chat counts as "declining". Do you really want to '
        'go?',
    'dh.chat.stay': 'Stay',
    'dh.chat.leaveDecline': 'Leave & decline',
    'dh.chat.sayHello': 'Say hi to {name}!',
    'dh.chat.fiveMinutes':
        'You have 5 minutes to get to know each other. Afterwards you '
        'both decide: match or keep searching?',
    'dh.chat.icebreakerBtn': 'Send conversation starter',
    'dh.chat.hint': 'Message...',
    'dh.chat.timeUp':
        'The 5 minutes are up!\nWould you like to see each other again?',
    'dh.chat.decline': 'Decline',    'dh.chat.accept': 'Accept',
    'dh.chat.bothMustAccept':
        'Both must press "Accept" for a spark.',
    'dh.chat.voted': 'You have voted. Waiting for the other side...',
    'dh.chat.resultPending':
        'As soon as both have decided, you will see the result.',
    'dh.chat.backToOverview': 'Back to overview',
    'dh.chat.sendFailed': 'Message could not be sent.',
    'dh.prefs.title': 'Dating Hour: preferences',
    'dh.prefs.header': 'Your Dating Hour preferences',
    'dh.prefs.headerSub':
        'These settings help us connect you with matching people. You can '
        'adjust them before every event.',
    'dh.prefs.ageRange': '{min} to {max} years',
    'dh.prefs.sectionJoin': 'Participation',
    'dh.prefs.autoJoin': 'Automatically join again',
    'dh.prefs.autoJoinSub':
        'If enabled, you will automatically take part in the next Dating '
        'Hour event.',
    'dh.prefs.traitHint':
        'Pick a trait or type your own. It flows into matching as a soft '
        'factor.',
    'dh.prefs.traitHintField':
        'e.g. "Good vibes", "Deep conversations"...',
    'dh.prefs.habits': 'Habits (optional)',
    'dh.prefs.habitsSub':
        'People with matching habits are suggested to you first during '
        'matching, nobody is excluded.',
    'dh.prefs.save': 'Save preferences',
    'dh.prefs.saveNote':
        'Saving does NOT sign you up. You confirm your participation '
        'separately with "I am in" on the event screen.',
    'dh.prefs.saved':
        'Preferences saved. You confirm your participation with "I am '
        'in" on the event day.',
    'dh.event.joinConfirmTitle': 'Join the event?',
    'dh.event.join': 'I am in',
    'dh.event.joined': "You're in for the Dating Hour event!",
    'dh.event.left': 'You left the event.',
    'dh.event.bye': 'See you next time!',
    'dh.event.noThanks': 'No, thanks',
    'dh.event.yesPlease': 'Yes, please',
    'dh.event.title': 'Dating Hour',
    'dh.event.ended': 'Dating hour ended',
    'dh.event.joinNow': 'Join now & chat',
    'dh.event.leave': 'Leave',
    'dh.event.setPrefs': 'Set preferences',
    'dh.event.nextIn': 'Next event in {d}',
    'dh.event.searching': 'Searching...',
    'dh.event.loadError': 'Loading error',
    'dh.event.searchingPartner': 'Looking for a partner for you...',
    'dh.event.toChat': 'To chat',
    'dh.event.nonePlanned':
        'Currently no Dating Hour event is planned.',
    'dh.event.remaining': '{d} left',
    'dh.event.startIn': 'Starts in {d}',
    'dh.event.chatsRunning': 'Chats are running.',
    'dh.event.waitStart': 'Waiting for the start.',
    'dh.event.participating': 'You are in!',

    'profile.edit.filters': 'Filters & preferences',
    'profile.edit.radiusMode': 'Define search radius by',
    'profile.edit.maxDistance': 'Maximum distance: {km} km',
    'profile.edit.minAge': 'Minimum age: {age} years',
    'profile.edit.maxAge': 'Maximum age: {age} years',
    'profile.edit.bio': 'Bio',
    'profile.edit.music': 'Music',
    'profile.edit.musicSub':
        'Which music describes you? Your taste flows into the connection '
        'score.',
    'profile.edit.habits': 'Habits',
    'profile.edit.habitsSub':
        'How do you feel about these? Your answers influence who you see '
        'in "Find your Match". Only people who consume at most as much '
        'as you do are shown.',
    'profile.edit.interests': 'Interests',
    'profile.edit.personality': 'Personality test',
    'profile.edit.personalityDone':
        'You have completed the test. You can retake it at any time.',
    'profile.edit.personalityOpen': 'Show others who you really are.',
    'profile.edit.personalityRetake': 'Retake test',
    'profile.edit.personalityStart': 'Start personality test',
    'profile.edit.saved': 'Profile saved',
    'profile.edit.savedNoSync':
        'Saved locally. Server sync failed, please save again later.',
    'profile.edit.missingFields':
        'Some information is missing or some fields are invalid (marked '
        'in red).',
    'profile.edit.missingFieldsHint':
        'Some information is missing or some fields are invalid (marked '
        'in red). Please check the form.',
    'profile.edit.birthDateMissing': 'Please choose your date of birth',
    'profile.edit.photoUpdated': 'Profile picture updated.',
    'profile.edit.photoUploadError': 'Upload failed: {error}',
    'profile.edit.photoPolicyBlocked':
        'This image does not meet our guidelines and was not uploaded.',
    'profile.edit.photoNsfwTitle': 'Image not approved',
    'profile.edit.photoNsfwBody':
        'This image was classified on your device as potentially '
        'inappropriate and will not be uploaded.',
    'profile.edit.photoNsfwChoice': 'What would you like to do?',
    'profile.edit.photoNsfwAppeal': 'Appeal',
    'profile.edit.photoNsfwUnderstood': 'Understood',
    'profile.edit.photoNsfwVerdict': 'Local verdict: {label} ({score} %).',
    'profile.edit.photoNsfwNotUploaded':
        'This image will not be uploaded as your profile picture.',
    'profile.edit.photoOkTitle': 'Image checked',
    'profile.edit.photoOkBody':
        'Your image is fine and can be used.',
    'profile.edit.photoOkBtn': 'Continue',
    'profile.edit.appealSubmitted':
        'Appeal submitted. We will notify you about the decision.',
    'profile.edit.appealFailed':
        'Appeal could not be submitted. Please try again later.',
    'profile.appeal.approvedTitle': 'Image approved',
    'profile.appeal.approvedBody':
        'Your appeal has been reviewed: the image is approved. Would you '
        'like to use it as your profile picture now?',
    'profile.appeal.useBtn': 'Use now',
    'profile.appeal.applied': 'Profile picture updated.',
    'profile.appeal.rejectedTitle': 'Image rejected',
    'profile.appeal.rejectedBody':
        'Your appeal has been reviewed: the image was rejected and cannot '
        'be used. Please choose a different profile picture.',
    'profile.appeal.okBtn': 'Understood',
    'profile.edit.photoNsfwOther': 'Choose another image',
    'profile.edit.locationDetected': 'Location detected and applied.',
    'profile.edit.locationFailed':
        'Location could not be determined. Please enter it manually or '
        'grant permission.',
    'profile.edit.locationSuspicious':
        'Note: This location differs greatly from your previous locations '
        'on this device.',
    'profile.edit.locationError': 'Location detection failed: {error}',
    'profile.edit.unsavedTitle': 'Unsaved changes',
    'profile.edit.unsavedBody':
        'Your profile changes have not been saved yet. What would you '
        'like to do?',
    'profile.edit.unsavedDiscard': 'Discard',
    'profile.detail.aboutMe': 'About me',
    'profile.detail.noBio': 'No bio yet.',
    'profile.detail.interests': 'Interests',
    'profile.detail.commonWithYou': 'Shared with you',
    'profile.detail.more': 'More',
    'profile.detail.music': 'Music',
    'profile.detail.sameTaste': 'Same taste',
    'profile.detail.noMusic': 'No music taste given.',
    'common.refresh': 'Refresh',
    'settings.twoFactor': 'Two-factor protection (2FA)',
    'settings.twoFactorActive': 'Active: login only with authenticator code',
    'settings.twoFactorSetup':
        'Secure your login with an authenticator app',
    'settings.notifyLikesSub': 'When someone likes you',
    'settings.notifyMessagesSub': 'When someone writes to you',
    'settings.unifiedPush': 'Push without Google (UnifiedPush)',
    'settings.unifiedPushOn': 'Active - endpoint registered.',
    'settings.unifiedPushOff':
        'Requires a distributor app like ntfy (F-Droid). FCM stays active '
        'in the Play variant.',
    'settings.blurSub':
        'Protection from inappropriate content: images from your match are '
        'only shown after confirmation (long press to report).',
    'settings.keyBackup': 'Encrypted key backup',
    'settings.keyBackupSub':
        'Backs up the private identity of your end-to-end encryption '
        '(password-encrypted, AES-256-GCM). Only with it can you chat '
        'encrypted again after switching devices. Losing both backup AND '
        'password is irreversible.',
    'settings.backupCreateSub': 'Generates an encrypted code',
    'settings.backupRestoreSub': 'Overwrites the current E2E identity',
    'settings.safetyCenter': 'Safety Center',
    'settings.safetyCenterSub':
        'Help with harassment or stalking, blocking, reporting',
    // Privacy & account
    'privacy.title': 'Privacy & account',
    'privacy.yourData': 'Your data',
    'privacy.dataInfo':
        'Wisp stores profile information, location data (only if you '
        'share it), photos, chats, likes and matches. All data is '
        'transferred encrypted and stored only as long as your account is '
        'active.',
    'privacy.export': 'Export my data',
    'privacy.exportSub': 'JSON download of all personal data',
    'privacy.exportFailed': 'Export failed',
    'privacy.import': 'Import my data',
    'privacy.importSub': 'Restore your JSON data export',
    'privacy.importTitle': 'Import data',
    'privacy.importBody':
        'Paste the contents of your export file '
        '(wisp_data_export.json) here. Profile, settings and '
        'preferences will be restored.',
    'privacy.importHint': '{ ... paste JSON here ... }',
    'privacy.importApply': 'Import',
    'privacy.importInvalid':
        'The pasted JSON could not be read. Please check the content.',
    'privacy.importDone': 'Data imported successfully.',
    'privacy.importFailed': 'Import failed',
    'privacy.accountSection': 'Sign-in',
    'privacy.accountInfo':
        'Email and password changes require your current password. For '
        'email changes you confirm the new address via a link sent to '
        'both inboxes.',
    'privacy.changeEmail': 'Change email address',
    'privacy.changeEmailInfo':
        'You will receive a confirmation link at your old AND new '
        'address. The change only becomes active after confirmation.',
    'privacy.changeEmailSent':
        'Confirmation link sent to both email addresses.',
    'privacy.changePassword': 'Change password',
    'privacy.changePasswordDone': 'Password changed.',
    'privacy.changeFailed': 'Change failed',
    'auth.passwordCurrent': 'Current password',
    'auth.passwordNew': 'New password',
    'auth.passwordConfirm': 'Repeat new password',
    'privacy.processors': 'Processors',
    'privacy.processorsInfo':
        'The following service providers (Art. 28 GDPR) process data on '
        'our behalf. Chat content is end-to-end encrypted and is not '
        'processed by any provider.',
    'privacy.processorSupabase': 'Hosting, database, authentication (EU)',
    'privacy.processorGoogle': 'Push notifications',
    'privacy.processorBrevo': 'Transactional emails (confirmation, reset)',
    'privacy.processorCloudflare': 'CAPTCHA (Turnstile) and TURN relay',
    'privacy.processorNetlify': 'Hosting of the auth/CAPTCHA page',
    'privacy.processorApple': 'App Store distribution',
    'privacy.consent': 'Consents',
    'privacy.location': 'Location sharing',
    'privacy.locationSub':
        'You can revoke location sharing at any time in your device\'s '
        'system settings.',
    'privacy.openLocationSettings': 'Open location settings',
    'privacy.push': 'Push notifications',
    'privacy.pushSub':
        'Opens your device\'s app settings, where you can control '
        'notifications.',
    'privacy.openAppSettings': 'Open app settings',
    'privacy.dangerZone': 'Danger zone',
    'privacy.deleteAccount': 'Delete account permanently',
    'privacy.deleteAccountSub':
        'GDPR Art. 17: Right to erasure. All data will be removed.',
    'privacy.deleteTitle': 'Delete account?',
    'privacy.deleteBody':
        'This step cannot be undone. All your data (profile, photos, '
        'chats, matches, likes) will be permanently deleted.',
    'privacy.deleteConfirm': 'Delete permanently',
    'privacy.deleteFailed': 'Account could not be deleted',
    'common.save': 'Save',
    'common.cancel': 'Cancel',
    'common.ok': 'OK',
    'common.yes': 'Yes',
    'common.no': 'No',
    'common.continue': 'Continue',
    'common.back': 'Back',
    'common.loading': 'Loading…',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email or password is wrong.',
    'error.notConfirmed': 'Please confirm your email address first.',
    'error.alreadyRegistered':
        'This email address is already registered. Please log in directly '
        'or reset your password.',
    'error.rateLimited': 'Too many requests in a short time. Please wait a '
        'moment and try again.',
    'error.weakPassword': 'The password is too weak. Please choose a longer '
        'one with upper/lower case letters, numbers and special characters.',
    'error.captchaRejected': 'The security check was rejected by the server. '
        'Please try again.',
    'error.signupFailed': 'Sign-up failed on the server. Please try again '
        'later.',
    'error.loginFailed': 'Log-in failed. Please try again.',
    'error.generic': 'Something went wrong. Please try again.',
  },
};
