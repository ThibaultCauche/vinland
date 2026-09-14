import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/share_inbox_config.dart';

/// Un partage recu, tel que renvoye par GET /shares/<username> (voir
/// share-inbox/server.py).
class ReceivedShare {
  final String id;
  final String from;
  final String type; // track | album | playlist
  final String itemId;
  final String title;
  final String subtitle;
  final DateTime? createdAt;

  const ReceivedShare({
    required this.id,
    required this.from,
    required this.type,
    required this.itemId,
    required this.title,
    required this.subtitle,
    required this.createdAt,
  });

  factory ReceivedShare.fromJson(Map<String, dynamic> json) => ReceivedShare(
        id: json['id']?.toString() ?? '',
        from: json['from']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        itemId: json['itemId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}

/// Client du petit service "boite de reception" maison (voir share-inbox/ a
/// la racine du repo) : permet d'envoyer un partage titre/album/playlist
/// CIBLE a un ami precis (contrairement au partage externe de
/// deep_link_service.dart, qui compte sur un outil tiers -- SMS/WhatsApp --
/// pour faire passer le lien). Meme principe que AvatarService/
/// DownloadWorkerService : cle partagee cote config gitignoree, service
/// maison fait le reste.
class ShareInboxService {
  bool get isConfigured => kShareInboxBaseUrl.isNotEmpty;

  Future<bool> sendShare({
    required String to,
    required String from,
    required String type,
    required String itemId,
    required String title,
    required String subtitle,
  }) async {
    if (!isConfigured) return false;
    try {
      final response = await http
          .post(
            Uri.parse('$kShareInboxBaseUrl/shares'),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Key': kShareInboxApiKey,
            },
            body: jsonEncode({
              'to': to,
              'from': from,
              'type': type,
              'itemId': itemId,
              'title': title,
              'subtitle': subtitle,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<List<ReceivedShare>> fetchShares(String username) async {
    if (!isConfigured) return [];
    try {
      final response = await http
          .get(Uri.parse('$kShareInboxBaseUrl/shares/$username'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final raw = jsonDecode(response.body) as List;
      return raw
          .map((e) => ReceivedShare.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> dismissShare(String username, String shareId) async {
    if (!isConfigured) return;
    try {
      await http.delete(
        Uri.parse('$kShareInboxBaseUrl/shares/$username/$shareId'),
        headers: {'X-Api-Key': kShareInboxApiKey},
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      // Best-effort : au pire le partage reapparait au prochain
      // rechargement, pas grave (l'utilisateur peut re-ignorer).
    }
  }
}
