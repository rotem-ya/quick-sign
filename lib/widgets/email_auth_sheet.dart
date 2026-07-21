import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/auth_service.dart';

/// Email + password sign-in / sign-up — the universal option for users without
/// a Google or Apple account, working on Android, iOS, and web alike. Returns
/// true if the user became signed in.
Future<bool?> showEmailAuthDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _EmailAuthDialog(),
  );
}

class _EmailAuthDialog extends StatefulWidget {
  const _EmailAuthDialog();

  @override
  State<_EmailAuthDialog> createState() => _EmailAuthDialogState();
}

class _EmailAuthDialogState extends State<_EmailAuthDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendlyError(S s, Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return s['authInvalidEmail'];
        case 'email-already-in-use':
          return s['authEmailInUse'];
        case 'weak-password':
          return s['authWeakPassword'];
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return s['authWrongCreds'];
      }
    }
    return s['authError'];
  }

  Future<void> _submit() async {
    final s = S.of(context);
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = s['emailRequired']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = _signUp
          ? await AuthService.instance.registerWithEmail(email, pass)
          : await AuthService.instance.signInWithEmail(email, pass);
      if (!mounted) return;
      if (user != null) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final s = S.of(context);
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = s['emailRequired']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s['resetSent'])));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_signUp ? s['createAccount'] : s['signInWithEmail']),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: s['email']),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: s['password']),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _busy ? null : _forgot,
              child: Text(s['forgotPassword']),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed:
                  _busy ? null : () => setState(() => _signUp = !_signUp),
              child: Text(_signUp ? s['toggleSignIn'] : s['toggleSignUp']),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(s['cancel']),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_signUp ? s['createAccount'] : s['signInAction']),
        ),
      ],
    );
  }
}
