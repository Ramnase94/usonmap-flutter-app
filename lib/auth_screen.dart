
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

const authPink = Color(0xFFFF4FA3);
const authPurple = Color(0xFF7C3AED);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegister = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

 
Future<void> _submit() async {
  if (!_formKey.currentState!.validate()) return;

  try {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_isRegister) {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } else {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isRegister
              ? 'Account तयार झाले! 🎉'
              : 'Login यशस्वी झाला! ❤️',
        ),
      ),
    );
  } on FirebaseAuthException catch (e) {
    if (!mounted) return;

    String message;

    switch (e.code) {
      case 'email-already-in-use':
        message = 'हा Email आधीच नोंदणीकृत आहे.';
        break;
      case 'invalid-email':
        message = 'कृपया योग्य Email टाका.';
        break;
      case 'weak-password':
        message = 'अधिक मजबूत Password वापरा.';
        break;
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        message = 'Email किंवा Password चुकीचा आहे.';
        break;
      case 'network-request-failed':
        message = 'Internet कनेक्शन तपासा.';
        break;
      case 'too-many-requests':
        message = 'खूप प्रयत्न झाले. थोड्या वेळाने पुन्हा प्रयत्न करा.';
        break;
      default:
        message = 'Login/Register झाले नाही. पुन्हा प्रयत्न करा. (${e.code})';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('काहीतरी चूक झाली. कृपया पुन्हा प्रयत्न करा.'),
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF10091F),
              Color(0xFF35134C),
              Color(0xFF792B76),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        color: authPink,
                        size: 70,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'UsOnMap ♥',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister
                            ? 'Create your little world together'
                            : 'Welcome back to your little world',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isRegister ? 'Create Account' : 'Sign In',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 22),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Colors.white),
                              decoration: _decoration(
                                'Email address',
                                Icons.email_outlined,
                              ),
                              validator: (value) {
                                if (value == null ||
                                    !value.contains('@') ||
                                    !value.contains('.')) {
                                  return 'Valid email address टाका';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _hidePassword,
                              style: const TextStyle(color: Colors.white),
                              decoration: _decoration(
                                'Password',
                                Icons.lock_outline_rounded,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _hidePassword = !_hidePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.length < 6) {
                                  return 'Password किमान 6 अक्षरांचा असावा';
                                }
                                return null;
                              },
                            ),
                            if (!_isRegister)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Password reset Firebase जोडल्यावर सुरू होईल.',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: authPink,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _submit,
                              child: Text(
                                _isRegister ? 'Create Account' : 'Sign In',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isRegister = !_isRegister;
                                });
                              },
                              child: Text(
                                _isRegister
                                    ? 'Already have an account? Sign In'
                                    : 'New here? Create Account',
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'POWERED BY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '∞  RTechnologies',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: authPink),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      errorStyle: const TextStyle(color: Color(0xFFFFB3C9)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: authPink, width: 1.5),
      ),
    );
  }
}
