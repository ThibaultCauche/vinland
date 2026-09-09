import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/discord_config.dart';

enum FeedbackType { bug, idea, other }

extension FeedbackTypeLabel on FeedbackType {
  String get label => switch (this) {
        FeedbackType.bug => 'Bug',
        FeedbackType.idea => 'Idee',
        FeedbackType.other => 'Autre',
      };
}

/// Envoie un retour utilisateur dans le salon Discord dedie via un webhook :
/// `thread_name` cree un nouveau fil pour chaque message (necessite que le
/// webhook soit configure sur un salon de type Forum, voir discord_config.dart).
class FeedbackService {
  Future<bool> send({
    required FeedbackType type,
    required String title,
    required String description,
    required String username,
    required String appVersion,
    required String platform,
  }) async {
    if (kDiscordFeedbackWebhookUrl.isEmpty) return false;
    try {
      final response = await http
          .post(
            Uri.parse(kDiscordFeedbackWebhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'thread_name': '[${type.label}] $title',
              'content': '**Par** : $username\n'
                  '**Version** : $appVersion ($platform)\n\n'
                  '$description',
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }
}
