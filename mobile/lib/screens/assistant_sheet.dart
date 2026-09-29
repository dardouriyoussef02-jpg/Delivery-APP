import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../models/ai_suggestion.dart';
import '../models/delivery.dart';
import '../services/api_client.dart';
import '../services/contact_actions.dart';
import '../state/assistant_controller.dart';
import '../widgets/section_card.dart';

/// The AI feature the client asked for, end to end:
/// understand the note -> show the suggested next action -> let the driver
/// review/edit the prepared message -> send it only when the driver says so.
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({super.key});

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<AssistantSheet> {
  late final TextEditingController _noteController;
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    final controller = context.read<AssistantController>();
    _noteController = TextEditingController(text: controller.note)
      ..addListener(_onNoteChanged);
    _messageController = TextEditingController(text: controller.editedBody)
      ..addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    _noteController.removeListener(_onNoteChanged);
    _messageController.removeListener(_onMessageChanged);
    _noteController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onNoteChanged() => context.read<AssistantController>().setNote(_noteController.text);

  void _onMessageChanged() =>
      context.read<AssistantController>().setEditedBody(_messageController.text);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssistantController>();
    final delivery = controller.delivery;

    // Keep the message field in sync when a fresh suggestion arrives.
    if (controller.phase == AssistantPhase.ready &&
        _messageController.text != controller.editedBody) {
      _messageController.value = TextEditingValue(
        text: controller.editedBody,
        selection: TextSelection.collapsed(offset: controller.editedBody.length),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brand.withValues(alpha: 0.40),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppTheme.onBrand, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI assistant', style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                      if (delivery != null)
                        Text(
                          '${delivery.id} \u00b7 ${delivery.customer.fullName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _Body(
                noteController: _noteController,
                messageController: _messageController,
              ),
            ),
          ),
          const _BottomBar(),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.inkFaint.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.noteController, required this.messageController});

  final TextEditingController noteController;
  final TextEditingController messageController;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssistantController>();

    return switch (controller.phase) {
      AssistantPhase.idle => _InputPhase(noteController: noteController),
      AssistantPhase.thinking => const _ThinkingPhase(),
      AssistantPhase.ready => _ResultPhase(messageController: messageController),
      AssistantPhase.sending => const _ThinkingPhase(sending: true),
      AssistantPhase.sent => const _SentPhase(),
      AssistantPhase.failure => _ErrorPhase(noteController: noteController),
    };
  }
}

/// Phase 1 - choose the note and the channel, then analyse.
class _InputPhase extends StatelessWidget {
  const _InputPhase({required this.noteController});

  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssistantController>();
    final delivery = controller.delivery;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (delivery != null && delivery.notes.length > 1) ...[
          Text('Pick a note', style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final note in delivery.notes)
                ChoiceChip(
                  label: Text(
                    note.fromCustomer ? 'Customer note' : 'Dispatcher note',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  selected: controller.note.trim() == note.text.trim(),
                  onSelected: (_) {
                    noteController.text = note.text;
                    controller.setNote(note.text);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text('Note or situation', style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
        const SizedBox(height: 8),
        TextField(
          controller: noteController,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            counterText: '',
            hintText: 'Paste or type what the customer/dispatcher said\u2026',
          ),
        ),
        const SizedBox(height: 8),
        Text('Message channel', style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final channel in MessageChannel.values)
              ChoiceChip(
                avatar: Icon(channel.icon, size: 15),
                label: Text(channel.label),
                selected: controller.channel == channel,
                onSelected: (_) => controller.setChannel(channel),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.24)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, size: 17, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The assistant only prepares a suggestion and a draft. Nothing is '
                  'sent until you review it and press Send.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Phase 2 - the agent is working (trace is shown once the answer lands).
class _ThinkingPhase extends StatelessWidget {
  const _ThinkingPhase({this.sending = false});

  final bool sending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = sending
        ? const ['Sending your approved message']
        : const [
            'Understanding the note',
            'Reading delivery context',
            'Checking company guidelines',
            'Drafting the customer message',
          ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: AppTheme.brand.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 20),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(step, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'This usually takes about a second.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Phase 3 - situation, next action, editable message and the trace.
class _ResultPhase extends StatelessWidget {
  const _ResultPhase({required this.messageController});

  final TextEditingController messageController;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssistantController>();
    final suggestion = controller.suggestion;
    final delivery = controller.delivery;
    final theme = Theme.of(context);

    if (suggestion == null || delivery == null) return const SizedBox.shrink();

    final overLimit = controller.bodyLength > AppConfig.maxMessageChars;
    final underLimit = controller.bodyLength < AppConfig.minMessageChars;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SituationCard(suggestion: suggestion),
        const SizedBox(height: 12),
        _ActionCard(suggestion: suggestion),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text('Message for ${suggestion.message.recipient}',
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
            ),
            if (controller.editing)
              const MetaPill(icon: Icons.edit_outlined, label: 'edited', color: AppTheme.accent),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final channel in MessageChannel.values)
              ChoiceChip(
                avatar: Icon(channel.icon, size: 15),
                label: Text(channel.label),
                selected: controller.channel == channel,
                onSelected: (_) => controller.setChannel(channel),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: messageController,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            errorText: overLimit
                ? 'Too long - max ${AppConfig.maxMessageChars} characters'
                : underLimit
                    ? 'A little more detail, please (min ${AppConfig.minMessageChars})'
                    : null,
            counterText: '',
            suffixIcon: Padding(
              padding: const EdgeInsets.only(bottom: 26, right: 12),
              child: Text(
                '${controller.bodyLength}/${AppConfig.maxMessageChars}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: overLimit ? AppTheme.danger : AppTheme.inkFaint,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.isBusy ? null : controller.regenerate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Regenerate'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => ContactActions.share(controller.editedBody),
                icon: const Icon(Icons.ios_share_outlined, size: 18),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Review the text above - it is sent exactly as written.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _TraceSection(suggestion: suggestion),
      ],
    );
  }
}

class _SituationCard extends StatelessWidget {
  const _SituationCard({required this.suggestion});

  final AiSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.26)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppTheme.brand.withValues(alpha: 0.30)),
            ),
            child: Icon(situationIcon(suggestion.situation.type),
                size: 20, color: AppTheme.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        suggestion.situation.label,
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 15.5),
                      ),
                    ),
                    _ConfidenceBadge(percent: suggestion.confidencePercent),
                  ],
                ),
                const SizedBox(height: 6),
                Text(suggestion.reasoning, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 80
        ? AppTheme.success
        : percent >= 60
            ? AppTheme.warning
            : AppTheme.inkMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        '$percent%',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.suggestion});

  final AiSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brand.withValues(alpha: 0.16),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 18, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                'Suggested next action',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(actionIcon(suggestion.recommendedAction.type),
                  size: 22, color: AppTheme.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.recommendedAction.label,
                      style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(suggestion.recommendedAction.reason, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TraceSection extends StatelessWidget {
  const _TraceSection({required this.suggestion});

  final AiSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (suggestion.trace.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          dense: true,
          iconColor: AppTheme.inkMuted,
          collapsedIconColor: AppTheme.inkMuted,
          title: Text(
            'How I got here (${suggestion.trace.length} steps)',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          children: [
            for (final step in suggestion.trace)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      step.ok ? Icons.check_circle_outline : Icons.error_outline,
                      size: 16,
                      color: step.ok ? AppTheme.success : AppTheme.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${step.label} \u00b7 ${step.ms}ms',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(step.detail, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Reference ${suggestion.requestId}',
              style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _SentPhase extends StatelessWidget {
  const _SentPhase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(color: AppTheme.success.withValues(alpha: 0.25), blurRadius: 30),
              ],
            ),
            child: const Icon(Icons.check_circle_outline, size: 44, color: AppTheme.success),
          ),
          const SizedBox(height: 14),
          Text('Message sent', style: theme.textTheme.titleLarge?.copyWith(fontSize: 19)),
          const SizedBox(height: 8),
          Text(
            'Your customer has been updated. The conversation is logged on the delivery.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorPhase extends StatelessWidget {
  const _ErrorPhase({required this.noteController});

  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssistantController>();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline, size: 18, color: AppTheme.danger),
                    const SizedBox(width: 8),
                    Text('The assistant could not answer',
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(controller.error ?? 'Unknown error', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (controller.note.trim().isEmpty)
            TextField(
              controller: noteController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Describe the situation in one line\u2026',
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: controller.analyze,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// Fixed bottom action: one clear primary action per phase.
class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssistantController>();

    final child = switch (controller.phase) {
      AssistantPhase.idle => FilledButton.icon(
          onPressed: controller.note.trim().isEmpty ? null : controller.analyze,
          icon: const Icon(Icons.auto_awesome, size: 19),
          label: const Text('Analyse note'),
        ),
      AssistantPhase.thinking => const FilledButton(
          onPressed: null,
          child: Text('Working\u2026'),
        ),
      AssistantPhase.ready => FilledButton.icon(
          onPressed: controller.bodyWithinLimits && !controller.isBusy
              ? controller.send
              : null,
          icon: const Icon(Icons.send_outlined, size: 19),
          label: Text('Send to ${controller.suggestion?.message.recipient ?? 'customer'}'),
        ),
      AssistantPhase.sending => const FilledButton(onPressed: null, child: Text('Sending\u2026')),
      AssistantPhase.sent => OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      AssistantPhase.failure => OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
    };

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: child,
    );
  }
}
