import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          // Gradient background adds depth
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.pink[100]!,
              Colors.pink[50]!,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  // Logo and image area
                  Container(
                    height: 250,
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          // Background image
                          Positioned.fill(
                            child: Image.asset(
                              'assets/images/captain_lilyimage.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Optional overlay to ensure text visibility
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Login content card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 4,
                    shadowColor: Colors.black26,
                    child: const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: LoginContent(),
                    ),
                  ),
                  const SizedBox(height: 50), // Extra space at the bottom
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginContent extends ConsumerStatefulWidget {
  const LoginContent({super.key});

  @override
  ConsumerState<LoginContent> createState() => _LoginContentState();
}

// Only updating the _LoginContentState class since that's where the changes are needed

class _LoginContentState extends ConsumerState<LoginContent> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Update only the _login and _googleSignIn methods in _LoginContentState

  Future<void> _login() async {
    // Basic validation
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = "Please enter your email";
      });
      return;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = "Please enter your password";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print("Logging in with email: ${_emailController.text.trim()}");
      // Use Firebase Auth through the provider
      await ref.read(authProvider.notifier).login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      // Check if login was successful
      final authState = ref.read(authProvider);
      if (authState.isLoggedIn) {
        print("Login successful, navigating to home");
        // Use go_router to navigate to home
        if (mounted) {
          context.go('/home');
        }
      } else if (authState.errorMessage != null) {
        print("Login failed: ${authState.errorMessage}");
        setState(() {
          _errorMessage = authState.errorMessage;
        });
      }
    } catch (e) {
      print("Login exception: $e");
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Updated _googleSignIn method with better error handling and fallback navigation

  Future<void> _googleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print("Starting Google sign-in process");

      // Call the sign-in method from auth provider
      await ref.read(authProvider.notifier).signInWithGoogle();

      // Wait a moment for auth state to update
      await Future.delayed(Duration(milliseconds: 300));

      // Check auth state
      final authState = ref.read(authProvider);

      // Check if Firebase Auth has a current user regardless of our state
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (authState.isLoggedIn || firebaseUser != null) {
        print("Google sign-in successful, navigating to home");
        if (mounted) {
          context.go('/home');
        }
      } else if (authState.errorMessage != null) {
        print("Google sign-in failed with error: ${authState.errorMessage}");
        setState(() {
          _errorMessage = authState.errorMessage;
        });
      } else {
        print("Google sign-in failed without specific error");
        setState(() {
          _errorMessage = "Sign-in failed. Please try again.";
        });
      }
    } catch (e) {
      print("Google sign-in exception: $e");

      // Check if Firebase Auth has a current user despite the error
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        print("Exception occurred but user is authenticated. Navigating to home.");
        if (mounted) {
          context.go('/home');
        }
        return;
      }

      setState(() {
        _errorMessage = "Google sign-in failed: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.pink[400];
    final currentTime = DateTime.now().toUtc();
    final formattedTime =
        '${currentTime.year}-${currentTime.month.toString().padLeft(2, '0')}-${currentTime.day.toString().padLeft(2, '0')} '
        '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}:${currentTime.second.toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Login',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF8D6E63), // Brownish color for elegance
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: 'Email',
            floatingLabelStyle: TextStyle(color: primaryColor),
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor!, width: 1.5),
            ),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            floatingLabelStyle: TextStyle(color: primaryColor),
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor!, width: 1.5),
            ),
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red[700], fontSize: 13),
            ),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Text(
              'Login',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),

        // Fixed Google Sign-in button to prevent overflow
        SizedBox(
          width: double.infinity,
          height: 60,
          child: OutlinedButton(
            onPressed: _isLoading ? null : _googleSignIn,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey[300]!),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, // Center the content
              children: [
                Icon(Icons.g_mobiledata, size: 30, color: Colors.red),
                const SizedBox(width: 8),
                const Text(
                  'Sign in with Google',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.go('/forgot-password'),
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Forgot password?',
            style: TextStyle(
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 4), // Small gap between buttons
        TextButton(
          onPressed: () => context.go('/signup'),
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            "Don't have an account? Sign up",
            style: TextStyle(
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 8), // Extra bottom spacing

        // Current date and time
        Text(
          formattedTime,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[400],
          ),
        ),
        Text(
          'Lilydebug',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
}