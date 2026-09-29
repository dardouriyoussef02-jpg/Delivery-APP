import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../services/api_client.dart';
import '../state/session_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _urlController = TextEditingController();
  bool _obscure = true;
  bool _showAdvanced = false;

  /// false = sign in, true = create a new driver account.
  bool _signUp = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionController>();
    _urlController.text = session.baseUrl;
    if (session.driverEmail.isNotEmpty) _emailController.text = session.driverEmail;

    // Explains why the driver landed back here (expired/revoked session).
    final notice = session.notice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        session.clearNotice();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = context.read<SessionController>();
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    await session.setBaseUrl(_urlController.text);
    final ok = _signUp
        ? await session.signUp(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          )
        : await session.signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.errorMessage ?? 'Sign-in failed')),
      );
    }
  }

  void _toggleMode() {
    setState(() {
      _signUp = !_signUp;
      _confirmController.clear();
    });
    // Clear any stale validation errors from the other mode.
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          // Luminous lime bloom behind the hero.
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.bloom(alpha: 0.26))),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    // ------------------------------------------------ hero
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            gradient: AppTheme.brandGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.brand.withValues(alpha: 0.4),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.local_shipping_outlined,
                              color: AppTheme.onBrand, size: 30),
                        ),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delivery Driver',
                                style: TextStyle(
                                  color: AppTheme.ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'AI co-pilot for every stop',
                                style: TextStyle(
                                  color: AppTheme.inkMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 44),
                    Text(
                      _signUp ? 'Create account' : 'Welcome back',
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _signUp
                          ? 'Register with your e-mail to join the fleet. Your AI '
                              'delivery assistant is waiting inside.'
                          : 'Sign in to start your route. Your AI delivery assistant '
                              'is waiting inside.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 26),

                    // ------------------------------------------------ form
                    if (_signUp) ...[
                      TextFormField(
                        controller: _nameController,
                        autofillHints: const [AutofillHints.name],
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) => value == null || value.trim().length < 2
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (value) =>
                          value == null || !value.contains('@') ? 'Enter a valid e-mail' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.length < (_signUp ? 8 : 4)
                              ? (_signUp
                                  ? 'At least 8 characters'
                                  : 'At least 4 characters')
                              : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_signUp) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (value) => value != _passwordController.text
                            ? 'Passwords do not match'
                            : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                        icon: Icon(
                          _showAdvanced ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                        ),
                        label: Text(_showAdvanced ? 'Hide API settings' : 'API settings'),
                      ),
                    ),
                    if (_showAdvanced) ...[
                      TextFormField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Backend base URL',
                          hintText: AppConfig.defaultBaseUrl,
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: session.busy
                            ? null
                            : () async {
                                await session.setBaseUrl(_urlController.text);
                                final result = await session.testConnection();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(result.message),
                                    backgroundColor:
                                        result.ok ? null : AppTheme.danger,
                                  ),
                                );
                              },
                        icon: const Icon(Icons.wifi_tethering_outlined, size: 18),
                        label: const Text('Test connection'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: session.busy ? null : _submit,
                      child: session.busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: AppTheme.onBrand),
                            )
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: session.busy ? null : _toggleMode,
                      child: Text(
                        _signUp
                            ? 'Already have an account? Sign in'
                            : 'New driver? Create an account',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ------------------------------------------------ hint
                    if (!_signUp)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.brand.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: AppTheme.brand.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_awesome_outlined,
                                size: 17, color: AppTheme.brand),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Sign in with your fleet account (demo credentials are '
                                'configured in services/ai-agent/.env). The AI assistant '
                                'runs on the bundled agent service - start it with '
                                '"npm start" in services/ai-agent.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
