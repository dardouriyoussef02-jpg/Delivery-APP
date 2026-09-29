/// Models for the AI assistant's response, mirroring the contract of
/// `POST /api/v1/agent/suggest`.
library;

import 'delivery.dart' show MessageChannel;

/// One step the agent executed while answering (transparency for the driver).
class TraceStep {
  const TraceStep({
    required this.tool,
    required this.label,
    required this.ok,
    required this.ms,
    required this.detail,
  });

  final String tool;
  final String label;
  final bool ok;
  final int ms;
  final String detail;

  factory TraceStep.fromJson(Map<String, dynamic> json) => TraceStep(
        tool: json['tool'] as String? ?? '',
        label: json['label'] as String? ?? '',
        ok: json['ok'] as bool? ?? true,
        ms: (json['ms'] as num?)?.toInt() ?? 0,
        detail: json['detail'] as String? ?? '',
      );
}

class Situation {
  const Situation({required this.type, required this.label});

  final String type;
  final String label;

  factory Situation.fromJson(Map<String, dynamic> json) => Situation(
        type: json['type'] as String? ?? 'general_note',
        label: json['label'] as String? ?? '',
      );
}

class RecommendedAction {
  const RecommendedAction({required this.type, required this.label, required this.reason});

  final String type;
  final String label;
  final String reason;

  factory RecommendedAction.fromJson(Map<String, dynamic> json) => RecommendedAction(
        type: json['type'] as String? ?? '',
        label: json['label'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
      );
}

class DraftMessage {
  const DraftMessage({
    required this.channel,
    required this.recipient,
    required this.body,
    required this.charCount,
  });

  final MessageChannel channel;
  final String recipient;
  final String body;
  final int charCount;

  DraftMessage copyWith({MessageChannel? channel, String? body, int? charCount}) => DraftMessage(
        channel: channel ?? this.channel,
        recipient: recipient,
        body: body ?? this.body,
        charCount: charCount ?? this.charCount,
      );

  factory DraftMessage.fromJson(Map<String, dynamic> json) {
    final body = json['body'] as String? ?? '';
    return DraftMessage(
      channel: MessageChannel.fromWire(json['channel'] as String?),
      recipient: json['recipient'] as String? ?? '',
      body: body,
      charCount: (json['charCount'] as num?)?.toInt() ?? body.runes.length,
    );
  }
}

class AiSuggestion {
  const AiSuggestion({
    required this.requestId,
    required this.deliveryId,
    required this.provider,
    required this.note,
    required this.situation,
    required this.confidence,
    required this.reasoning,
    required this.recommendedAction,
    required this.message,
    required this.requiresApproval,
    required this.trace,
    required this.latencyMs,
    required this.createdAt,
  });

  final String requestId;
  final String deliveryId;
  final String provider;
  final String note;
  final Situation situation;
  final double confidence;
  final String reasoning;
  final RecommendedAction recommendedAction;
  final DraftMessage message;
  final bool requiresApproval;
  final List<TraceStep> trace;
  final int latencyMs;
  final DateTime createdAt;

  /// 0..1 confidence rendered as a friendly percentage.
  int get confidencePercent => (confidence * 100).round();

  factory AiSuggestion.fromJson(Map<String, dynamic> json) => AiSuggestion(
        requestId: json['requestId'] as String? ?? '',
        deliveryId: json['deliveryId'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        note: json['note'] as String? ?? '',
        situation: Situation.fromJson((json['situation'] as Map?)?.cast<String, dynamic>() ?? const {}),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        reasoning: json['reasoning'] as String? ?? '',
        recommendedAction: RecommendedAction.fromJson(
          (json['recommendedAction'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        message: DraftMessage.fromJson((json['message'] as Map?)?.cast<String, dynamic>() ?? const {}),
        requiresApproval: json['requiresApproval'] as bool? ?? true,
        trace: ((json['trace'] as List?) ?? const [])
            .map((step) => TraceStep.fromJson((step as Map).cast<String, dynamic>()))
            .toList(),
        latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
