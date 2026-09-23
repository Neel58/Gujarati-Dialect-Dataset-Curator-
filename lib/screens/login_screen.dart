import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _agreedToTerms = false;
  bool _awaitingEmailConfirmation = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _mapError(dynamic e) {
    if (e is AuthException) {
      if (e.message.contains('Invalid login credentials')) {
        return 'Incorrect email or password.';
      }
      if (e.message.contains('User already registered')) {
        return 'An account with this email already exists.';
      }
      return e.message;
    }
    return e.toString();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSignUp && !_agreedToTerms) {
      _showSnack('You must agree to the terms to sign up.');
      return;
    }

    setState(() => _isLoading = true);
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    try {
      if (_isSignUp) {
        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {
            'consented_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
        if (res.session == null) {
          setState(() => _awaitingEmailConfirmation = true);
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } catch (e) {
      _showSnack(_mapError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showSnack('Please enter your email to reset password.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _showSnack('Password reset email sent (if account exists).');
    } catch (e) {
      _showSnack(_mapError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_awaitingEmailConfirmation) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm Email')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_email_unread, size: 64, color: Colors.deepPurple),
                const SizedBox(height: 24),
                const Text(
                  'Please confirm your email address.',
                  style: TextStyle(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'We sent a confirmation link to your email. Click it, then come back and sign in.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _awaitingEmailConfirmation = false;
                      _isSignUp = false;
                    });
                  },
                  child: const Text('Return to Sign In'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Sign Up' : 'Sign In')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || v.trim().isEmpty || !v.contains('@')) ? 'Valid email required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
              ),
              if (_isSignUp) ...[
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('I am 18+ and agree my recordings may be used in an open Gujarati dialect dataset.'),
                  value: _agreedToTerms,
                  onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(_isSignUp ? 'Already have an account? Sign In' : 'Need an account? Sign Up'),
              ),
              if (!_isSignUp)
                TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Forgot Password?'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
