import 'dart:convert';

import 'package:delivery_driver/core/formatters.dart';
import 'package:delivery_driver/models/ai_suggestion.dart';
import 'package:delivery_driver/models/delivery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Delivery', () {
    test('parses a delivery payload from the API', () {
      final json = jsonDecode(_deliveryJson) as Map<String, dynamic>;
      final delivery = Delivery.fromJson(json);

      expect(delivery.id, 'DLV-1042');
      expect(delivery.status, DeliveryStatus.inTransit);
      expect(delivery.customer.fullName, 'Sanne de Vries');
      expect(delivery.customer.channel, MessageChannel.sms);
      expect(delivery.address.singleLine, contains('Kanalstraat'));
      expect(delivery.notes, hasLength(2));
      expect(delivery.events, hasLength(3));
      expect(delivery.hasAccessInstructions, isTrue);
    });

    test('primaryNote prefers the newest customer note', () {
      final delivery = Delivery.fromJson(jsonDecode(_deliveryJson) as Map<String, dynamic>);
      final primary = delivery.primaryNote;

      expect(primary, isNotNull);
      expect(primary!.fromCustomer, isTrue);
      expect(primary.text, contains('Gate code'));
    });

    test('unknown status falls back to pending', () {
      final map = jsonDecode(_deliveryJson) as Map<String, dynamic>;
      map['status'] = 'weird';
      final delivery = Delivery.fromJson(map);
      expect(delivery.status, DeliveryStatus.pending);
    });

    test('copyWith updates status and keeps identity', () {
      final delivery = Delivery.fromJson(jsonDecode(_deliveryJson) as Map<String, dynamic>);
      final updated = delivery.copyWith(status: DeliveryStatus.delivered);

      expect(updated.id, delivery.id);
      expect(updated.status, DeliveryStatus.delivered);
      expect(delivery.status, DeliveryStatus.inTransit, reason: 'original untouched');
    });
  });

  group('AiSuggestion', () {
    test('parses the agent response including the trace', () {
      final suggestion = AiSuggestion.fromJson(jsonDecode(_suggestionJson) as Map<String, dynamic>);

      expect(suggestion.deliveryId, 'DLV-1042');
      expect(suggestion.situation.type, 'access_instructions');
      expect(suggestion.recommendedAction.type, 'follow_access_instructions');
      expect(suggestion.message.channel, MessageChannel.sms);
      expect(suggestion.message.charCount, suggestion.message.body.length);
      expect(suggestion.requiresApproval, isTrue);
      expect(suggestion.trace, hasLength(4));
      expect(suggestion.confidencePercent, 89);
      expect(validateBounds(suggestion), isTrue);
    });
  });

  group('formatters', () {
    final now = DateTime(2026, 9, 28, 15, 40);

    test('formats times and windows', () {
      expect(timeOfDay(DateTime(2026, 9, 28, 9, 5)), '09:05');
      expect(
        timeWindow(DateTime(2026, 9, 28, 15, 30), DateTime(2026, 9, 28, 16, 30)),
        '15:30 – 16:30',
      );
    });

    test('formats relative times around now', () {
      expect(relativeTime(now.add(const Duration(minutes: 12)), now: now), 'in 12 min');
      expect(relativeTime(now.subtract(const Duration(minutes: 45)), now: now), '45 min ago');
      expect(relativeTime(now, now: now), 'now');
    });

    test('formats money and distance', () {
      expect(money(24.9, 'EUR'), '\u20ac24.90');
      expect(distance(4.25), '4.3 km');
      expect(plural(1, 'note'), '1 note');
      expect(plural(3, 'note'), '3 notes');
    });

    test('previews long notes with an ellipsis', () {
      expect(preview('Short note'), 'Short note');
      expect(preview('x' * 200), endsWith('\u2026'));
      expect(preview('x' * 200).runes.length, 90);
    });
  });
}

/// Every suggestion the API returns has to respect the message guardrails.
bool validateBounds(AiSuggestion suggestion) {
  final body = suggestion.message.body;
  return body.runes.length >= 40 && body.runes.length <= 320 && suggestion.confidence <= 1;
}

const _deliveryJson = '''
{
  "id": "DLV-1042",
  "status": "in_transit",
  "zone": "Riverside",
  "sequence": 3,
  "driverId": "DRV-77",
  "windowStart": "2026-09-28T15:30:00.000Z",
  "windowEnd": "2026-09-28T16:30:00.000Z",
  "eta": "2026-09-28T15:52:00.000Z",
  "distanceKm": 4.2,
  "parcels": 2,
  "codAmount": 24.9,
  "currency": "EUR",
  "address": {
    "line1": "18 Kanalstraat",
    "line2": "Flat 4B, 2nd floor",
    "city": "Rotterdam",
    "postalCode": "3011 AB",
    "lat": 51.9161,
    "lng": 4.4795,
    "accessHint": "Buzzer 4B is broken - call on arrival"
  },
  "customer": {
    "id": "CUS-8821",
    "firstName": "Sanne",
    "lastName": "de Vries",
    "phone": "+31 6 1234 5678",
    "preferredChannel": "sms",
    "language": "nl",
    "rating": 4.8
  },
  "notes": [
    {
      "id": "NOTE-1",
      "author": "customer",
      "createdAt": "2026-09-28T14:34:00.000Z",
      "text": "Gate code 4482, please leave the parcels with my neighbour at no. 20 if I do not open."
    },
    {
      "id": "NOTE-2",
      "author": "dispatcher",
      "createdAt": "2026-09-28T14:50:00.000Z",
      "text": "Customer asked for a delivery update when the driver is 10 minutes away."
    }
  ],
  "events": [
    { "at": "2026-09-28T14:15:00.000Z", "type": "assigned", "label": "Assigned to driver" },
    { "at": "2026-09-28T14:50:00.000Z", "type": "picked_up", "label": "Parcels picked up at hub" },
    { "at": "2026-09-28T15:38:00.000Z", "type": "in_transit", "label": "On the way" }
  ],
  "history": []
}
''';

const _suggestionJson = '''
{
  "requestId": "SUG-abc123",
  "deliveryId": "DLV-1042",
  "provider": "mock",
  "note": "Gate code 4482",
  "situation": { "type": "access_instructions", "label": "Access instructions given" },
  "confidence": 0.89,
  "reasoning": "The note contains a gate code and a neighbour instruction.",
  "recommendedAction": {
    "type": "follow_access_instructions",
    "label": "Follow the access instructions in the note",
    "reason": "Using the code avoids a failed attempt at a gated building."
  },
  "message": {
    "channel": "sms",
    "recipient": "Sanne",
    "body": "Hi Sanne, your driver is on the way to 18 Kanalstraat and will use the access instructions from your note. Reply here if anything changes - ref DLV-1042.",
    "charCount": 153
  },
  "requiresApproval": true,
  "trace": [
    { "tool": "get_delivery", "label": "Reading delivery context", "ok": true, "ms": 1, "detail": "Sanne @ 18 Kanalstraat" },
    { "tool": "list_delivery_events", "label": "Checking previous attempts", "ok": true, "ms": 1, "detail": "3 events" },
    { "tool": "search_guidelines", "label": "Looking up company guidelines", "ok": true, "ms": 0, "detail": "SOP-ACCESS" },
    { "tool": "draft_message", "label": "Drafting the customer message", "ok": true, "ms": 1, "detail": "validated" }
  ],
  "latencyMs": 12,
  "createdAt": "2026-09-28T15:40:00.000Z"
}
''';
