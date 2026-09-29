import 'package:delivery_driver/models/ai_suggestion.dart';
import 'package:delivery_driver/models/delivery.dart';
import 'package:delivery_driver/services/ai_agent_service.dart';
import 'package:delivery_driver/services/api_client.dart';
import 'package:delivery_driver/state/assistant_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stub of the agent API so the whole review-then-send flow can be tested
/// without a backend.
class _FakeAgent implements AiAgentService {
  _FakeAgent(this.suggestion);

  AiSuggestion suggestion;
  bool sent = false;
  String? lastBody;

  @override
  Future<AiSuggestion> suggest({
    required String deliveryId,
    String? note,
    MessageChannel? channel,
  }) async {
    return suggestion;
  }

  @override
  Future<String> sendApprovedMessage({
    required String deliveryId,
    required MessageChannel channel,
    required String recipient,
    required String body,
    String? action,
  }) async {
    sent = true;
    lastBody = body;
    return 'MSG-0001';
  }

  @override
  Future<({bool ok, String provider, String dataMode})> health() async =>
      (ok: true, provider: 'mock', dataMode: 'demo');
}

void main() {
  late _FakeAgent agent;
  late AssistantController controller;
  late Delivery delivery;

  setUp(() {
    agent = _FakeAgent(_suggestion());
    controller = AssistantController(agent);
    delivery = _delivery();
  });

  test('prepare resets the session for a stop', () {
    controller.prepare(delivery);

    expect(controller.phase, AssistantPhase.idle);
    expect(controller.delivery!.id, 'DLV-1042');
    expect(controller.note, contains('Gate code'));
    expect(controller.channel, MessageChannel.sms);
    expect(controller.suggestion, isNull);
  });

  test('analyze stores the suggestion and makes the draft editable', () async {
    controller.prepare(delivery);
    await controller.analyze();

    expect(controller.phase, AssistantPhase.ready);
    expect(controller.situationType, 'access_instructions');
    expect(controller.editedBody, agent.suggestion.message.body);
    expect(controller.bodyWithinLimits, isTrue);
    expect(controller.editing, isFalse);
  });

  test('editing the draft marks it as changed by the driver', () async {
    controller.prepare(delivery);
    await controller.analyze();

    controller.setEditedBody('Hi Sanne, je chauffeur is onderweg - ref DLV-1042.');

    expect(controller.editing, isTrue);
    expect(controller.bodyLength, greaterThan(0));
  });

  test('send only fires after the driver approved', () async {
    controller.prepare(delivery);
    await controller.analyze();

    final ok = await controller.send();

    expect(ok, isTrue);
    expect(agent.sent, isTrue);
    expect(agent.lastBody, agent.suggestion.message.body);
    expect(controller.phase, AssistantPhase.sent);
    expect(controller.sentMessageId, 'MSG-0001');
  });

  test('refuses to send a draft outside the guardrails', () async {
    controller.prepare(delivery);
    await controller.analyze();
    controller.setEditedBody('Too short');

    final ok = await controller.send();

    expect(ok, isFalse);
    expect(agent.sent, isFalse);
    expect(controller.phase, AssistantPhase.failure);
    expect(controller.error, contains('320'));
  });

  test('reports a failing backend as a readable error', () async {
    final failing = _FailingAgent();
    final failingController = AssistantController(failing);
    failingController.prepare(delivery);

    await failingController.analyze();

    expect(failingController.phase, AssistantPhase.failure);
    expect(failingController.error, isNotEmpty);
  });
}

Delivery _delivery() => Delivery.fromJson({
      'id': 'DLV-1042',
      'status': 'in_transit',
      'zone': 'Riverside',
      'sequence': 3,
      'driverId': 'DRV-77',
      'windowStart': '2026-09-28T15:30:00.000Z',
      'windowEnd': '2026-09-28T16:30:00.000Z',
      'eta': '2026-09-28T15:52:00.000Z',
      'distanceKm': 4.2,
      'parcels': 2,
      'codAmount': 24.9,
      'currency': 'EUR',
      'address': {
        'line1': '18 Kanalstraat',
        'line2': '',
        'city': 'Rotterdam',
        'postalCode': '3011 AB',
        'lat': 51.9161,
        'lng': 4.4795,
        'accessHint': 'Buzzer is broken',
      },
      'customer': {
        'id': 'CUS-8821',
        'firstName': 'Sanne',
        'lastName': 'de Vries',
        'phone': '+31 6 1234 5678',
        'preferredChannel': 'sms',
        'language': 'nl',
      },
      'notes': [
        {
          'id': 'NOTE-1',
          'author': 'customer',
          'createdAt': '2026-09-28T14:34:00.000Z',
          'text': 'Gate code 4482, leave with the neighbour if I do not open.',
        },
      ],
      'events': [
        {'at': '2026-09-28T14:15:00.000Z', 'type': 'assigned', 'label': 'Assigned'},
      ],
      'history': <Map<String, dynamic>>[],
    });

AiSuggestion _suggestion() => AiSuggestion.fromJson({
      'requestId': 'SUG-1',
      'deliveryId': 'DLV-1042',
      'provider': 'mock',
      'note': 'Gate code 4482',
      'situation': {'type': 'access_instructions', 'label': 'Access instructions given'},
      'confidence': 0.89,
      'reasoning': 'The note contains a gate code and a neighbour instruction.',
      'recommendedAction': {
        'type': 'follow_access_instructions',
        'label': 'Follow the access instructions in the note',
        'reason': 'Using the code avoids a failed attempt at a gated building.',
      },
      'message': {
        'channel': 'sms',
        'recipient': 'Sanne',
        'body':
            'Hi Sanne, your driver is on the way to 18 Kanalstraat and will use the access instructions from your note - ref DLV-1042.',
        'charCount': 124,
      },
      'requiresApproval': true,
      'trace': [
        {
          'tool': 'get_delivery',
          'label': 'Reading delivery context',
          'ok': true,
          'ms': 1,
          'detail': 'Sanne @ 18 Kanalstraat',
        },
      ],
      'latencyMs': 8,
      'createdAt': '2026-09-28T15:40:00.000Z',
    });

class _FailingAgent implements AiAgentService {
  @override
  Future<AiSuggestion> suggest({
    required String deliveryId,
    String? note,
    MessageChannel? channel,
  }) async {
    throw ApiException('The assistant is unavailable right now.', statusCode: 503);
  }

  @override
  Future<String> sendApprovedMessage({
    required String deliveryId,
    required MessageChannel channel,
    required String recipient,
    required String body,
    String? action,
  }) async =>
      '';

  @override
  Future<({bool ok, String provider, String dataMode})> health() async =>
      (ok: false, provider: 'unknown', dataMode: 'unknown');
}
