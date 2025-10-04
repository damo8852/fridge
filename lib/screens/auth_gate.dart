import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth.dart';
import 'home.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.onAuthStateChanged,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const _LoginScreen();
        return const HomePage();
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  bool _busy = false;
  String? _err;

  Future<void> _run(Future Function() f) async {
    setState(() { _busy = true; _err = null; });
    try { await f(); } catch (e) { setState(() => _err = e.toString()); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 2,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.kitchen_rounded, size: 56),
                  const SizedBox(height: 12),
                  Text('Welcome to Fridge', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Reduce waste. Save money. Eat fresher.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),

                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_err!, style: TextStyle(color: theme.colorScheme.error)),
                    ),

                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(AuthService.instance.signInWithGoogle),
                    icon: const Icon(Icons.login),
                    label: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(AuthService.instance.signInWithMicrosoft),
                    icon: const Icon(Icons.account_circle),
                    label: const Text('Continue with Microsoft'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : () => _run(AuthService.instance.signInAnonymously),
                    child: const Text('Continue as guest'),
                  ),

                  if (_busy) const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: CircularProgressIndicator(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

