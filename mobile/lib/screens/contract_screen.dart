import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../services/contract_service.dart';
import '../state/session_controller.dart';
import '../widgets/section_card.dart';
import 'home_shell.dart';

/// The onboarding gate: a driver reads the partnership agreement and types
/// their name to sign it.
///
/// It is the *only* thing a signed-in but unsigned driver can reach, so it has
/// to be a complete screen in its own right - including a way out (sign out),
/// rather than a dead end. The moment the signature is accepted the backend
/// dispatches the open route, and [SessionController.contractSigned] flips,
/// which drops the driver straight into their queue.
class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key});

  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _signatureController = TextEditingController();

  ContractService? _service;
  ContractDocument? _document;
  bool _loading = true;
  String? _error;
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionController>();
    // Sensible default, but the legal name is the driver's to correct.
    if (session.driverName.isNotEmpty) {
      _signatureController.text = session.driverName;
    }
    _load();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service =
        _service ??= ContractService(context.read<SessionController>().api);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final document = await service.fetch();
      if (!mounted) return;
      setState(() {
        _document = document;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (!_acknowledged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm that you have read and accept the agreement.'),
        ),
      );
      return;
    }

    final session = context.read<SessionController>();
    final ok = await session.signContract(
      signatureName: _signatureController.text,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.errorMessage ?? 'Signing failed.')),
      );
    }
    // On success no navigation is needed: contractSigned notifies the shell
    // in app.dart, which rebuilds straight into the delivery queue.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.bloom(alpha: 0.26)),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _Hero(session: session),
                  const SizedBox(height: 24),
                  Text(
                    'Before your first route',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Dispatch only sends work to drivers who have signed the '
                    'partnership agreement. Read it below, then type your full '
                    'name to sign - your first stops arrive immediately after.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.inkMuted),
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.6),
                        ),
                      ),
                    )
                  else if (_error != null)
                    EmptyState(
                      icon: Icons.gavel_outlined,
                      title: 'Could not load the agreement',
                      message: _error!,
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    )
                  else
                    _buildForm(theme, session),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: session.busy ? null : session.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(ThemeData theme, SessionController session) {
    final document = _document!;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: document.title,
            trailing: document.version.isEmpty
                ? null
                : MetaPill(
                    icon: Icons.commit,
                    label: 'v${document.version}',
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final section in document.sections) ...[
                  Text(
                    section.heading,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    section.body,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.inkMuted, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                ],
                if (document.company.isNotEmpty)
                  Text(
                    document.company,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppTheme.brand),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Your signature',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _signatureController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Type your full name',
                    prefixIcon: Icon(Icons.draw_outlined),
                  ),
                  validator: (value) =>
                      value == null || value.trim().length < 2
                          ? 'Enter your full name'
                          : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acknowledged,
                      onChanged: session.busy
                          ? null
                          : (value) => setState(
                              () => _acknowledged = value ?? false,
                            ),
                      fillColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppTheme.brand
                            : AppTheme.surfaceHigh,
                      ),
                      checkColor: AppTheme.onBrand,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'I have read and accept this agreement. I understand '
                          'that deliveries are assigned to me by the company '
                          'only after I sign.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: session.busy ? null : _submit,
                  child: session.busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppTheme.onBrand,
                          ),
                        )
                      : const Text('Sign contract'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your name and the time of signing are recorded by the '
                  'company as your electronic signature.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brand.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.assignment_outlined,
              color: AppTheme.onBrand, size: 30),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ShiftFlow Logistics',
                style: TextStyle(
                  color: AppTheme.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                session.driverEmail,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.inkMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
