import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthState {
  final bool isLoggedIn;
  final User? user;
  final String? errorMessage;

  AuthState({
    required this.isLoggedIn,
    this.user,
    this.errorMessage
  });
}

class AuthNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AuthNotifier() : super(AuthState(isLoggedIn: false)) {
    // Initialize with current auth state
    _checkCurrentUser();

    // Listen to auth state changes
    _auth.authStateChanges().listen((User? user) {
      if (user != null) {
        state = AuthState(isLoggedIn: true, user: user);
        print("Auth state changed: User is logged in - ${user.uid}");
      } else {
        state = AuthState(isLoggedIn: false);
        print("Auth state changed: User is logged out");
      }
    });
  }

  void _checkCurrentUser() {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      state = AuthState(isLoggedIn: true, user: currentUser);
      print("Current user found: ${currentUser.uid}");
    } else {
      print("No current user found");
    }
  }

  Future<void> login(String email, String password) async {
    try {
      print("Attempting login with email: $email");
      // Sign in with Firebase
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print("Login successful for user: ${result.user?.uid}");

      // Update the user's last login timestamp
      try {
        await _firestore.collection('users').doc(result.user!.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
        print("Updated last login timestamp");
      } catch (e) {
        // If the user document doesn't exist yet, create it
        print("Creating new user document for: ${result.user!.uid}");
        await _firestore.collection('users').doc(result.user!.uid).set({
          'email': email,
          'isDriver': true,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }

      // Explicitly update the state
      state = AuthState(isLoggedIn: true, user: result.user);
    } catch (e) {
      print("Login error: $e");
      state = AuthState(isLoggedIn: false, errorMessage: e.toString());
    }
  }

  // Updated signInWithGoogle method to fix the type casting error

  Future<void> signInWithGoogle() async {
    try {
      print("Attempting Google sign-in");

      // Trigger the Google Sign In process
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in
        print("Google sign-in canceled by user");
        return;
      }

      print("Google sign-in account selected: ${googleUser.email}");

      try {
        // Obtain auth details from the Google Sign In
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

        // Create the Firebase credential
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        try {
          // Sign in to Firebase with the Google credential
          final UserCredential userCredential = await _auth.signInWithCredential(credential);
          final User? user = userCredential.user;

          if (user != null) {
            print("Google sign-in successful for user: ${user.uid}");

            // Check if this is a new user
            bool isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

            // Current timestamp for metadata
            final now = DateTime.now().toUtc();
            final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

            try {
              // Save user data to Firestore
              await _firestore.collection('users').doc(user.uid).set({
                'email': user.email,
                'displayName': user.displayName,
                'photoURL': user.photoURL,
                'isDriver': true,
                'lastLogin': FieldValue.serverTimestamp(),
                'createdAt': isNewUser ? FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
                'userMetadata': {
                  'lastUpdate': timestamp,
                  'userLogin': 'Lilydebug',
                }
              }, SetOptions(merge: true));

              print("User data saved to Firestore");
            } catch (firestoreError) {
              // If Firestore update fails, still consider the auth successful
              print("Firestore update error: $firestoreError");
            }

            // Explicitly update the state
            state = AuthState(isLoggedIn: true, user: user);
          } else {
            print("Firebase user is null after Google sign-in");
            state = AuthState(
                isLoggedIn: false,
                errorMessage: "Failed to sign in with Google: User is null"
            );
          }
        } catch (credentialError) {
          print("Firebase credential error: $credentialError");
          state = AuthState(
              isLoggedIn: false,
              errorMessage: "Failed to sign in with Google: $credentialError"
          );
        }
      } catch (authError) {
        print("Google authentication error: $authError");
        state = AuthState(
            isLoggedIn: false,
            errorMessage: "Failed to authenticate with Google: $authError"
        );
      }
    } catch (e) {
      print("Google sign-in error: $e");

      // For the specific type casting error, create a fallback approach
      if (e.toString().contains("type 'List<Object?>'" )) {
        // This is a known issue with the Google Sign In plugin
        // Let's create a fallback for when the user is actually authenticated
        if (_auth.currentUser != null) {
          print("Type error but user is authenticated. Creating fallback state.");
          final user = _auth.currentUser!;

          // Current timestamp for metadata
          final now = DateTime.now().toUtc();
          final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

          try {
            // Save user data to Firestore
            await _firestore.collection('users').doc(user.uid).set({
              'email': user.email,
              'displayName': user.displayName,
              'photoURL': user.photoURL,
              'isDriver': true,
              'lastLogin': FieldValue.serverTimestamp(),
              'userMetadata': {
                'lastUpdate': timestamp,
                'userLogin': 'Lilydebug',
              }
            }, SetOptions(merge: true));
          } catch (firestoreError) {
            print("Firestore fallback update error: $firestoreError");
          }

          // Set state to logged in despite the type error
          state = AuthState(isLoggedIn: true, user: user);
          return;
        }
      }

      // Default error handling
      state = AuthState(isLoggedIn: false, errorMessage: "Google sign-in failed: $e");
    }
  }

  Future<void> signUp(String email, String password) async {
    try {
      print("Attempting signup with email: $email");
      // Create user with Firebase
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print("Signup successful for user: ${result.user?.uid}");

      // Save user data to Firestore
      await _firestore.collection('users').doc(result.user!.uid).set({
        'email': email,
        'isDriver': true, // Since this is the Captain app
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      print("User data saved to Firestore");

      // Explicitly update the state
      state = AuthState(isLoggedIn: true, user: result.user);
    } catch (e) {
      print("Signup error: $e");
      state = AuthState(isLoggedIn: false, errorMessage: e.toString());
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      print("Sending password reset email to: $email");
      await _auth.sendPasswordResetEmail(email: email);
      print("Password reset email sent");
      // Don't change state, just return success
    } catch (e) {
      print("Password reset error: $e");
      state = AuthState(isLoggedIn: false, errorMessage: e.toString());
    }
  }

  Future<void> logout() async {
    try {
      print("Attempting logout");
      await _auth.signOut();
      await _googleSignIn.signOut(); // Sign out from Google as well
      print("Logout successful");
      state = AuthState(isLoggedIn: false);
    } catch (e) {
      print("Logout error: $e");
      // Even if there's an error, we should still consider the user logged out
      state = AuthState(isLoggedIn: false);
    }
  }

  bool isAuthenticated() => state.isLoggedIn;

  // Get current user id
  String? get currentUserId => _auth.currentUser?.uid;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});