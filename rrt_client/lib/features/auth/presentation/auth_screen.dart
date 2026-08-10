import 'package:flutter/material.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/app_state.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.auth,
    required this.storage,
    required this.onSignedIn,
  });

  final AuthService auth;
  final AppStateStorage storage;
  final VoidCallback onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _registering = false;
  bool _loading = false;
  String _role = 'tourist';

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.primary, size: 60),
                    const SizedBox(height: 16),
                    Text(
                      _registering ? 'Create account' : 'ThaiGuard',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('Emergency response service', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 32),
                    if (_registering) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Full name'),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone', hintText: '+79991234567'),
                      validator: (value) => value == null || value.length < 11 ? 'Enter phone number' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (value) => value == null || value.length < 6 ? 'At least 6 characters' : null,
                    ),
                    if (_registering) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'SMS code',
                          suffixIcon: TextButton(
                            onPressed: _loading ? null : _sendOtp,
                            child: const Text('Send code'),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Enter SMS code' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _role,
                        decoration: const InputDecoration(labelText: 'Account type'),
                        items: const [
                          DropdownMenuItem(value: 'tourist', child: Text('Tourist')),
                          DropdownMenuItem(value: 'rrt', child: Text('RRT crew')),
                          DropdownMenuItem(value: 'dispatcher', child: Text('Dispatcher')),
                        ],
                        onChanged: (value) => setState(() => _role = value ?? 'tourist'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _loading
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_registering ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading ? null : () => setState(() => _registering = !_registering),
                      child: Text(_registering ? 'I already have an account' : 'Create account'),
                    ),
                    TextButton.icon(
                      onPressed: _loading ? null : _editServer,
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Server settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendOtp() async {
    if (_phone.text.length < 11) {
      _show('Enter a valid phone number first.');
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.auth.sendOtp(_phone.text.trim());
      _show('SMS code requested. In development, check server logs.');
    } on ApiException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_registering) {
        await widget.auth.register(phone: _phone.text.trim(), code: _code.text.trim(), password: _password.text, fullName: _name.text.trim(), role: _role);
      } else {
        await widget.auth.login(_phone.text.trim(), _password.text);
      }
      widget.onSignedIn();
    } on ApiException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: await widget.storage.getBaseUrl());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.1.10:8080/api/v1'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await widget.storage.setBaseUrl(controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
