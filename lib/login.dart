import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'dart:math' as math;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoginView = true;
  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMessage;

  late final AnimationController _animCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _fadeAnimation;
  // animated background
  late final AnimationController _bgAnimCtrl;
  late final Animation<double> _bgAnimation;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.elasticOut,
    ));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    ));
    _animCtrl.forward();

    // background animation (slow, subtle)
    _bgAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _bgAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bgAnimCtrl, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _bgAnimCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAuthAction() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (_isLoginView) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        try {
          await cred.user?.sendEmailVerification();
        } catch (_) {
          // Silently ignore email verification errors
        }
      }
      // Success - clear any error messages and snackbars
      if (mounted) {
        // Clear any existing snackbars
        ScaffoldMessenger.of(context).clearSnackBars();
        setState(() {
          _errorMessage = null;
          _isLoading = false;
        });
      }
      // Auth state listener in main.dart will handle navigation automatically
      // No need to show any message on success
    } on FirebaseAuthException catch (e) {
      final errorMsg = _mapFirebaseAuthError(e);
      if (mounted) {
        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
        _showSnack(errorMsg);
      }
    } catch (e, stackTrace) {
      // Log the actual error for debugging
      debugPrint('Login error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Only show error if it's not a navigation-related issue
      // Sometimes navigation can throw exceptions that we should ignore
      if (mounted && FirebaseAuth.instance.currentUser == null) {
        // Only show error if user is not actually logged in
        final errorMsg = 'An error occurred. Please try again.';
        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
        _showSnack(errorMsg);
      } else if (mounted) {
        // If user is logged in, just clear loading state
        setState(() {
          _errorMessage = null;
          _isLoading = false;
        });
      }
    }
  }

  String _mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-not-found':
      case 'wrong-password':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'Email already in use. Try signing in.';
      case 'weak-password':
        return 'Password too weak (min 6 characters).';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  void _toggleView() {
    setState(() {
      _isLoginView = !_isLoginView;
      _errorMessage = null;
      _formKey.currentState?.reset();
    });
    _animCtrl.reset();
    _animCtrl.forward();
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnack('Enter your email to reset password.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('Password reset email sent. Check your inbox.');
    } on FirebaseAuthException catch (e) {
      _showSnack(_mapFirebaseAuthError(e));
    } catch (_) {
      _showSnack('Failed to send reset email.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Color? iconColor,
  }) {
    final primary = const Color(0xFF6366F1);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(
        icon,
        color: iconColor ?? primary,
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.15),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.red.shade400,
          width: 1.5,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.red.shade400,
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF6366F1);
    final secondary = const Color(0xFF8B5CF6);
    final accent = const Color(0xFF06B6D4);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Enhanced animated gradient background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(primary, secondary, math.sin(_bgAnimation.value * 2 * math.pi) * 0.5 + 0.5)!,
                        Color.lerp(secondary, accent, math.cos(_bgAnimation.value * 2 * math.pi) * 0.5 + 0.5)!,
                        const Color(0xFFF8FAFC),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.1),
                      child: CustomPaint(
                        painter: _LoginBackgroundPainter(_bgAnimation.value),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Main content with glassmorphism
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Enhanced logo section
                      ScaleTransition(
                        scale: _logoScale,
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [primary, secondary],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: primary.withValues(alpha: 0.4),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.sensors,
                                size: 42,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Smart Home',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isLoginView
                                  ? 'Welcome back! Sign in to continue'
                                  : 'Create your account to get started',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Glassmorphism card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: primary.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    // Email
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: _inputDecoration(
                                        label: 'Email',
                                        icon: Icons.email_outlined,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Email is required';
                                        }
                                        if (!RegExp(
                                          r'^[^@]+@[^@]+\.[^@]+',
                                        ).hasMatch(v.trim())) {
                                          return 'Enter a valid email';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                    // Password
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: !_showPassword,
                                      style: const TextStyle(color: Colors.white),
                                      decoration:
                                          _inputDecoration(
                                            label: 'Password',
                                            icon: Icons.lock_outline,
                                          ).copyWith(
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                _showPassword
                                                    ? Icons.visibility
                                                    : Icons.visibility_off,
                                                color: Colors.white.withValues(alpha: 0.7),
                                              ),
                                              onPressed: () => setState(
                                                () => _showPassword = !_showPassword,
                                              ),
                                            ),
                                          ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Password is required';
                                        }
                                        if (!_isLoginView && v.length < 6) {
                                          return 'Min 6 characters';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: TextButton(
                                            onPressed: _isLoading
                                                ? null
                                                : _sendPasswordReset,
                                            child: Text(
                                              'Forgot password?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.white.withValues(alpha: 0.8),
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        Flexible(
                                          child: TextButton(
                                            onPressed: _isLoading ? null : _toggleView,
                                            child: Text(
                                              _isLoginView
                                                  ? 'Create account →'
                                                  : '← Back to sign in',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    // Enhanced primary action button
                                    Container(
                                      width: double.infinity,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [primary, secondary],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: primary.withValues(alpha: 0.4),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _isLoading ? null : _handleAuthAction,
                                          borderRadius: BorderRadius.circular(16),
                                          child: Center(
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child: CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : Text(
                                                    _isLoginView ? 'Sign In' : 'Sign Up',
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w700,
                                                      color: Colors.white,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    // Separator
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            thickness: 1,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            _isLoginView ? 'or' : 'Secure',
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.6),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Divider(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            thickness: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    // Footer note
                                    Text(
                                      'By continuing, you agree to our Terms & Privacy Policy',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Enhanced error message
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade300,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red.shade200,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
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
          ),
        ],
      ),
    );
  }
}

// Background pattern painter for login page
class _LoginBackgroundPainter extends CustomPainter {
  final double animationValue;

  _LoginBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    // Draw animated circles
    for (int i = 0; i < 6; i++) {
      final radius = (80.0 + (i * 40.0));
      final x = size.width * (0.1 + (i * 0.15));
      final y = size.height * (0.2 + (i * 0.12));
      final offset = Offset(
        x + math.sin(animationValue * 2 * math.pi + i) * 40,
        y + math.cos(animationValue * 2 * math.pi + i) * 40,
      );

      canvas.drawCircle(offset, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
