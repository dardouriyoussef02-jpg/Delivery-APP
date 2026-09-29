import 'package:flutter/foundation.dart';

import '../models/ai_suggestion.dart';
import '../models/delivery.dart';
import '../services/ai_agent_service.dart';
import '../services/api_client.dart';

enum AssistantPhase { idle, thinking, ready, sending, sent, failure }

/// Drives the AI assistant bottom sheet:
/// analyse the note -> review the suggestion -> send the approved message.
class AssistantController extends ChangeNotifier {
  AssistantController(this._service, {this.onMessageSent});

  final AiAgentService _service;

  /// Called after a successful send so the app can refresh the notification
  /// feed (the demo backend answers with a customer reply).
  final void Function()? onMessageSent;

  AssistantPhase phase = AssistantPhase.idle;
  AiSuggestion? suggestion;
  String? error;

  /// Editable copy of the assistant's draft - the driver owns the final text.
  String editedBody = '';
  MessageChannel channel = MessageChannel.sms;
  String note = '';
  bool showTrace = false;
  bool editing = false;
  String? sentMessageId;

  Delivery? delivery;

  bool get isBusy =>
      phase == AssistantPhase.thinking || phase == AssistantPhase.sending;

  int get bodyLength => editedBody.runes.length;

  /// Situation type of the current suggestion, handy for widgets and tests.
  String? get situationType => suggestion?.situation.type;

  bool get bodyWithinLimits =>
      bodyLength >= AppConfig.minMessageChars && bodyLength <= AppConfig.maxMessageChars;

  /// Prepares a fresh session for one delivery (called when the sheet opens).
  void prepare(Delivery target, {String? initialNote, MessageChannel? preferredChannel}) {
    delivery = target;
    note = (initialNote ?? target.primaryNote?.text ?? '').trim();
    channel = preferredChannel ?? target.customer.channel;
    phase = AssistantPhase.idle;
    suggestion = null;
    error = null;
    editedBody = '';
    sentMessageId = null;
    showTrace = false;
    editing = false;
    notifyListeners();
  }

  void setNote(String value) {
    note = value;
    notifyListeners();
  }

  void setChannel(MessageChannel value) {
    channel = value;
    notifyListeners();
  }

  void setEditedBody(String value) {
    editedBody = value;
    if (!editing) editing = true;
    notifyListeners();
  }

  void toggleTrace() {
    showTrace = !showTrace;
    notifyListeners();
  }

  /// Runs the agent for the currently prepared delivery.
  Future<void> analyze() async {
    final target = delivery;
    if (target == null || note.trim().isEmpty) {
      error = 'Add a delivery note first.';
      phase = AssistantPhase.failure;
      notifyListeners();
      return;
    }

    phase = AssistantPhase.thinking;
    error = null;
    editing = false;
    sentMessageId = null;
    notifyListeners();

    try {
      final result = await _service.suggest(
        deliveryId: target.id,
        note: note,
        channel: channel,
      );
      suggestion = result;
      editedBody = result.message.body;
      channel = result.message.channel;
      phase = AssistantPhase.ready;
    } on ApiException catch (ex) {
      error = ex.message;
      phase = AssistantPhase.failure;
    } catch (_) {
      error = 'The assistant is unavailable right now. Please try again.';
      phase = AssistantPhase.failure;
    }

    notifyListeners();
  }

  Future<void> regenerate() => analyze();

  /// Called only after the driver tapped "Send to customer".
  Future<bool> send() async {
    final target = delivery;
    final current = suggestion;
    if (target == null || current == null) return false;

    if (!bodyWithinLimits) {
      error = 'Keep the message between ${AppConfig.minMessageChars} and '
          '${AppConfig.maxMessageChars} characters before sending.';
      phase = AssistantPhase.failure;
      notifyListeners();
      return false;
    }

    phase = AssistantPhase.sending;
    error = null;
    notifyListeners();

    try {
      final messageId = await _service.sendApprovedMessage(
        deliveryId: target.id,
        channel: channel,
        recipient: current.message.recipient,
        body: editedBody.trim(),
        action: current.recommendedAction.type,
      );
      sentMessageId = messageId;
      phase = AssistantPhase.sent;
      notifyListeners();
      onMessageSent?.call();
      return true;
    } on ApiException catch (ex) {
      error = ex.message;
      phase = AssistantPhase.failure;
      notifyListeners();
      return false;
    }
  }

  void reset() {
    phase = AssistantPhase.idle;
    suggestion = null;
    error = null;
    editedBody = '';
    sentMessageId = null;
    showTrace = false;
    editing = false;
    notifyListeners();
  }
}
