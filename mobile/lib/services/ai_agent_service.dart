import '../models/ai_suggestion.dart';
import '../models/delivery.dart';
import 'api_client.dart';

/// Client for the AI agent endpoints.
///
/// Flow: `suggest()` only ever returns a *proposal* (situation, next action,
/// draft message). `sendApprovedMessage()` is called exclusively after the
/// driver reviewed and approved the text in the UI.
class AiAgentService {
  AiAgentService(this._api);

  final ApiClient _api;

  Future<AiSuggestion> suggest({
    required String deliveryId,
    String? note,
    MessageChannel? channel,
  }) async {
    final data = await _api.post('/api/v1/agent/suggest', body: {
      'deliveryId': deliveryId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (channel != null) 'channel': channel.wire,
    });
    return AiSuggestion.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Sends the driver-approved text. Returns the message id assigned by the
  /// backend.
  Future<String> sendApprovedMessage({
    required String deliveryId,
    required MessageChannel channel,
    required String recipient,
    required String body,
    String? action,
  }) async {
    final data = await _api.post('/api/v1/agent/messages', body: {
      'deliveryId': deliveryId,
      'channel': channel.wire,
      'recipient': recipient,
      'body': body,
      if (action != null) 'action': action,
    });
    final payload = (data as Map?)?.cast<String, dynamic>();
    return payload?['messageId'] as String? ?? '';
  }

  /// Cheap health probe used by the connection check in Settings.
  Future<({bool ok, String provider, String dataMode})> health() async {
    final data = await _api.get('/health');
    final payload = (data as Map?)?.cast<String, dynamic>();
    return (
      ok: payload?['status'] == 'ok',
      provider: payload?['llmProvider'] as String? ?? 'unknown',
      dataMode: payload?['dataMode'] as String? ?? 'unknown',
    );
  }
}
