import 'dart:convert';
import 'dart:typed_data';

/// Un message du protocole Google Cast (CASTV2) : le `CastMessage` protobuf
/// echange avec la Chromecast, toujours a charge utile texte (JSON).
///
/// On encode/decode a la main ces six champs plutot que de tirer protobuf et
/// un fichier .proto genere : le format est fige depuis des annees et ne
/// sert qu'ici.
class CastMessage {
  const CastMessage({
    required this.namespace,
    required this.payload,
    this.sourceId = 'sender-0',
    this.destinationId = 'receiver-0',
  });

  final String sourceId;
  final String destinationId;
  final String namespace;

  /// JSON texte (payload_utf8).
  final String payload;

  /// La charge utile decodee, null si ce n'est pas un objet JSON.
  Map<String, dynamic>? get json {
    try {
      final value = jsonDecode(payload);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  String? get type => json?['type'] as String?;

  /// Message pret a ecrire sur la socket : longueur sur 4 octets (gros
  /// boutiste) puis le protobuf.
  Uint8List toFrame() {
    final body = BytesBuilder();
    _varintField(body, 1, 0); // protocol_version = CASTV2_1_0
    _stringField(body, 2, sourceId);
    _stringField(body, 3, destinationId);
    _stringField(body, 4, namespace);
    _varintField(body, 5, 0); // payload_type = STRING
    _stringField(body, 6, payload);
    final bytes = body.toBytes();
    final frame = ByteData(4)..setUint32(0, bytes.length);
    return (BytesBuilder()
          ..add(frame.buffer.asUint8List())
          ..add(bytes))
        .toBytes();
  }

  /// Decode le protobuf d'un message (sans les 4 octets de longueur).
  static CastMessage decode(Uint8List bytes) {
    var source = '';
    var destination = '';
    var namespace = '';
    var payload = '';
    var i = 0;
    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (i >= bytes.length) throw const FormatException('varint tronque');
        final b = bytes[i++];
        result |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) return result;
        shift += 7;
      }
    }

    while (i < bytes.length) {
      final key = readVarint();
      final field = key >> 3;
      switch (key & 7) {
        case 0:
          readVarint();
        case 1:
          i += 8;
        case 5:
          i += 4;
        case 2:
          final length = readVarint();
          if (i + length > bytes.length) {
            throw const FormatException('champ tronque');
          }
          final value = bytes.sublist(i, i + length);
          i += length;
          switch (field) {
            case 2:
              source = utf8.decode(value);
            case 3:
              destination = utf8.decode(value);
            case 4:
              namespace = utf8.decode(value);
            case 6:
              payload = utf8.decode(value);
          }
        default:
          throw FormatException('type de champ inconnu ${key & 7}');
      }
    }
    return CastMessage(
      sourceId: source,
      destinationId: destination,
      namespace: namespace,
      payload: payload,
    );
  }

  static void _writeVarint(BytesBuilder out, int value) {
    var v = value;
    while (v >= 0x80) {
      out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  static void _varintField(BytesBuilder out, int field, int value) {
    _writeVarint(out, field << 3);
    _writeVarint(out, value);
  }

  static void _stringField(BytesBuilder out, int field, String value) {
    final bytes = utf8.encode(value);
    _writeVarint(out, (field << 3) | 2);
    _writeVarint(out, bytes.length);
    out.add(bytes);
  }
}

/// Recoupe le flux d'octets de la socket en messages : un paquet TCP peut
/// contenir un bout de message, ou plusieurs.
class CastFrameDecoder {
  final _buffer = BytesBuilder();

  /// Messages complets disponibles apres l'ajout de [chunk].
  List<CastMessage> add(List<int> chunk) {
    _buffer.add(chunk);
    final messages = <CastMessage>[];
    final data = _buffer.takeBytes();
    var offset = 0;
    while (data.length - offset >= 4) {
      final length =
          ByteData.sublistView(data, offset, offset + 4).getUint32(0);
      if (data.length - offset - 4 < length) break;
      messages.add(CastMessage.decode(
        Uint8List.sublistView(data, offset + 4, offset + 4 + length),
      ));
      offset += 4 + length;
    }
    if (offset < data.length) _buffer.add(data.sublist(offset));
    return messages;
  }
}
