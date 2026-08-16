// Tests für WebRTCService-Härtung:
// - ice-config-Parsing (H-03, reine Funktion)
// - ICE-Cache ohne Netzwerkzugriff
// - Peer-Pinning im Signaling-Routing (fremde Absender werden verworfen)
import 'package:flutter_test/flutter_test.dart';

import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/webrtc_service.dart';

void main() {
  group('parseIceConfig', () {
    test('parst gültige Antwort inkl. TURN', () {
      final servers = WebRTCService.parseIceConfig(
        '{"iceServers":[{"urls":"stun:stun.example.com:3478"},'
        '{"urls":"turn:turn.example.com","username":"u","credential":"p"}],'
        '"ttlSeconds":7200}',
      );
      expect(servers.length, 2);
      expect(servers.first['urls'], 'stun:stun.example.com:3478');
      expect(servers.last['username'], 'u');
    });

    test('wirft StateError bei fehlendem iceServers', () {
      expect(
        () => WebRTCService.parseIceConfig('{"ttlSeconds":3600}'),
        throwsStateError,
      );
    });

    test('wirft StateError bei leerer Liste', () {
      expect(
        () => WebRTCService.parseIceConfig('{"iceServers":[]}'),
        throwsStateError,
      );
    });

    test('wirft FormatException bei kaputtem JSON', () {
      expect(
        () => WebRTCService.parseIceConfig('kein-json'),
        throwsFormatException,
      );
    });
  });

  group('ICE-Cache (H-03)', () {
    test('resolveIceServers liefert gecachte Server ohne Netzwerk', () async {
      final service = WebRTCService(EncryptionService());
      service.setIceServerCache(
        [
          {'urls': 'stun:stun.cached.example.com:3478'},
        ],
        const Duration(hours: 1),
      );

      final servers = await service.resolveIceServers();
      expect(servers.length, 1);
      expect(servers.first['urls'], 'stun:stun.cached.example.com:3478');
    });
  });

  group('Peer-Pinning im Signaling-Routing', () {
    test('Nachricht eines fremden Absenders wird verworfen (kein Crash)', () {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-victim';

      // Angreifer versucht, ein Offer zu injizieren.
      expect(
        () => service.routeSignalingForTesting({
          'type': 'offer',
          'from': 'attacker',
          'sdp': 'v=0 fake-sdp',
        }),
        returnsNormally,
      );
    });

    test('ICE-Kandidat ohne Pflichtfelder wird verworfen', () {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-victim';

      expect(
        () => service.routeSignalingForTesting({
          'type': 'ice',
          'from': 'peer-victim',
          'candidate': 'candidate:1 1 UDP 1 1.2.3.4 5 typ host',
        }),
        returnsNormally,
      );
    });

    test('unbekannter Signaltyp wird ignoriert', () {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-victim';

      expect(
        () => service.routeSignalingForTesting({
          'type': 'bogus',
          'from': 'peer-victim',
        }),
        returnsNormally,
      );
    });
  });
}