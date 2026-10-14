import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/cast/cast_message.dart';

void main() {
  const message = CastMessage(
    namespace: 'urn:x-cast:com.google.cast.media',
    sourceId: 'sender-0',
    destinationId: 'web-7',
    payload: '{"type":"LOAD","title":"Été indien"}',
  );

  test('un message encode se relit a l\'identique', () {
    final frame = message.toFrame();
    final decoded = CastFrameDecoder().add(frame).single;
    expect(decoded.namespace, message.namespace);
    expect(decoded.sourceId, 'sender-0');
    expect(decoded.destinationId, 'web-7');
    expect(decoded.json?['title'], 'Été indien');
    expect(decoded.type, 'LOAD');
  });

  test('les 4 premiers octets donnent la longueur du message', () {
    final frame = message.toFrame();
    final length = frame[0] << 24 | frame[1] << 16 | frame[2] << 8 | frame[3];
    expect(length, frame.length - 4);
  });

  test('un message coupe en plusieurs paquets est reconstitue', () {
    final frame = message.toFrame();
    final decoder = CastFrameDecoder();
    expect(decoder.add(frame.sublist(0, 3)), isEmpty);
    expect(decoder.add(frame.sublist(3, 20)), isEmpty);
    expect(decoder.add(frame.sublist(20)).single.type, 'LOAD');
  });

  test('deux messages dans le meme paquet sont tous les deux lus', () {
    final other = const CastMessage(namespace: 'ns', payload: '{"type":"PING"}')
        .toFrame();
    final messages = CastFrameDecoder().add([...message.toFrame(), ...other]);
    expect(messages.map((m) => m.type), ['LOAD', 'PING']);
  });

  test('une charge utile longue (> 127 octets) garde sa longueur', () {
    final long = CastMessage(
      namespace: 'ns',
      payload: '{"url":"${'x' * 500}"}',
    );
    final decoded = CastFrameDecoder().add(long.toFrame()).single;
    expect((decoded.json?['url'] as String).length, 500);
  });
}
