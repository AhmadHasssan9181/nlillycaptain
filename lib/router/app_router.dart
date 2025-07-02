import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/home_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/firebase_test_screen.dart';
import '../screens/driver_registration_screen.dart';
import '../screens/pending_screen.dart'; // Updated import

// Current timestamp and user login information
const String currentTimestamp = "2025-06-01 17:10:30";
const String currentUserLogin = "Lilydebug";

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

// Check if user is a taxi driver
Future<bool> isUserTaxiDriver(String userId) async {
  try {
    DocumentSnapshot doc = await FirebaseFirestore.instance.collection('Taxis').doc(userId).get();
    return doc.exists;
  } catch (e) {
    print("Error checking taxi status: $e");
    return false;
  }
}

// Router provider with splash screen
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (BuildContext context, GoRouterState state) {
      // Check Firebase Auth directly first
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn = firebaseUser != null || authState.isLoggedIn;

      // Log the redirect decision with timestamp and user login
      print("ROUTER REDIRECT [${currentTimestamp}] [${currentUserLogin}]:");
      print("  - Path: ${state.matchedLocation}");
      print("  - Firebase User: ${firebaseUser?.uid ?? 'null'}");
      print("  - Auth State LoggedIn: ${authState.isLoggedIn}");
      print("  - Combined LoggedIn: $isLoggedIn");

      // Don't redirect on splash screen or firebase test
      if (state.matchedLocation == '/' || state.matchedLocation == '/firebase-test') {
        return null;
      }

      final isGoingToLogin = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/forgot-password';

      // If not logged in and not going to login page, redirect to login
      if (!isLoggedIn && !isGoingToLogin) {
        print("  - Decision: Redirecting to /login");
        return '/login';
      }

      // If logged in and going to login page, redirect to driver check
      if (isLoggedIn && isGoingToLogin) {
        // We can't do async operations in redirect, so we'll handle the check
        // in the driver check route
        print("  - Decision: Redirecting to /driver-check");
        return '/driver-check';
      }

      // No redirect needed
      print("  - Decision: No redirect needed");
      return null;
    },
    routes: [
      // Splash screen route
      GoRoute(
        path: '/',
        builder: (context, state) {
          print("Building SplashScreen [${currentTimestamp}] [${currentUserLogin}]");
          return const SplashScreen();
        },
      ),

      // Firebase test route - accessible without auth
      GoRoute(
        path: '/firebase-test',
        name: 'firebase-test',
        builder: (context, state) {
          print("Building FirebaseTestScreen [${currentTimestamp}] [${currentUserLogin}]");
          return const FirebaseTestScreen();
        },
      ),

      // Driver check router - determines which screen to show based on status
      GoRoute(
          path: '/driver-check',
          builder: (context, state) {
            print("Checking driver status [${currentTimestamp}] [${currentUserLogin}]");
            final firebaseUser = FirebaseAuth.instance.currentUser;

            if (firebaseUser != null) {
              // Check if the user has a taxi record and what the status is
              FirebaseFirestore.instance
                  .collection('Taxis')
                  .doc(firebaseUser.uid)
                  .get()
                  .then((doc) {
                if (doc.exists) {
                  final data = doc.data() as Map<String, dynamic>?;
                  final status = data?['status'] as String?;

                  if (status == 'approved' || status == 'available' ||
                      status == 'online' || status == 'offline') {
                    // Already approved, go to home screen (main driver interface)
                    context.go('/home');
                  } else {
                    // Status is pending or rejected, show the pending screen
                    context.go('/pending');
                  }
                } else {
                  // No taxi document, go to registration
                  context.go('/driver-registration');
                }
              }).catchError((error) {
                print("Error checking taxi status: $error");
                // Default to driver registration on error
                context.go('/driver-registration');
              });
            } else {
              // No user, go to login
              context.go('/login');
            }

            // Show loading while checking
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFF4B6C)),
                    SizedBox(height: 20),
                    Text("Checking your account...")
                  ],
                ),
              ),
            );
          }
      ),

      // Auth route group
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          print("Building Auth Shell [${currentTimestamp}] [${currentUserLogin}]");
          return child;
        },
        routes: [
          // Login route
          GoRoute(
            path: '/login',
            name: 'login',
            builder: (context, state) {
              print("Building LoginScreen [${currentTimestamp}] [${currentUserLogin}]");
              return const LoginScreen();
            },
          ),
          // Signup route
          GoRoute(
            path: '/signup',
            name: 'signup',
            builder: (context, state) {
              print("Building SignupScreen [${currentTimestamp}] [${currentUserLogin}]");
              return const SignupScreen();
            },
          ),
          // Forgot password route
          GoRoute(
            path: '/forgot-password',
            name: 'forgot',
            builder: (context, state) {
              print("Building ForgotPasswordScreen [${currentTimestamp}] [${currentUserLogin}]");
              return const ForgotPasswordScreen();
            },
          ),
        ],
      ),

      // Driver Registration Route
      GoRoute(
        path: '/driver-registration',
        name: 'driver-registration',
        builder: (context, state) {
          print("Building DriverRegistrationScreen [${currentTimestamp}] [${currentUserLogin}]");

          // Check if the user already has a taxi registered
          final firebaseUser = FirebaseAuth.instance.currentUser;
          if (firebaseUser != null) {
            FirebaseFirestore.instance
                .collection('Taxis')
                .doc(firebaseUser.uid)
                .get()
                .then((doc) {
              if (doc.exists) {
                final data = doc.data() as Map<String, dynamic>?;
                final status = data?['status'] as String?;

                if (status == 'approved' || status == 'available' ||
                    status == 'online' || status == 'offline') {
                  // Already approved, go to home screen
                  context.go('/home');
                } else {
                  // Status is pending or rejected, show the pending screen
                  context.go('/pending');
                }
              }
            });
          }

          return const DriverRegistrationScreen();
        },
      ),

      // Pending Approval Route (renamed from DriverDashboard)
      GoRoute(
        path: '/pending',
        name: 'pending',
        builder: (context, state) {
          print("Building PendingScreen [${currentTimestamp}] [${currentUserLogin}]");
          return const PendingScreen();
        },
      ),

      // Home route - main driver interface (for approved drivers)
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) {
          print("Building HomeScreen [${currentTimestamp}] [${currentUserLogin}]");

          // Check if user is a driver and their status
          final firebaseUser = FirebaseAuth.instance.currentUser;
          if (firebaseUser != null) {
            FirebaseFirestore.instance
                .collection('Taxis')
                .doc(firebaseUser.uid)
                .get()
                .then((doc) {
              if (doc.exists) {
                final data = doc.data() as Map<String, dynamic>?;
                final status = data?['status'] as String?;

                if (status != 'approved' && status != 'available' &&
                    status != 'online' && status != 'offline') {
                  // Not approved yet, go to pending screen
                  context.go('/pending');
                }
              } else {
                // Not a driver, show driver registration
                context.go('/driver-registration');
              }
            }).catchError((error) {
              print("Error checking driver status: $error");
            });
          }

          // Update driver location when they access the home screen
          if (firebaseUser != null) {
            FirebaseFirestore.instance.collection('Taxis').doc(firebaseUser.uid).update({
              'lastHomeAccess': FieldValue.serverTimestamp(),
              'currentTimestamp': currentTimestamp,
              'currentUserLogin': currentUserLogin,
            }).catchError((error) {
              print("Error updating last access: $error");
            });
          }

          return const HomeScreen();
        },
      ),

      // Chat route
      GoRoute(
        path: '/chat/:rideId',
        name: 'chat',
        builder: (context, state) {
          final rideId = state.pathParameters['rideId']!;
          final passengerName = state.uri.queryParameters['name'] ?? 'Passenger';
          final passengerImage = state.uri.queryParameters['image'] ?? 'https://randomuser.me/api/portraits/women/44.jpg';

          print("Building ChatScreen for ride: $rideId [${currentTimestamp}] [${currentUserLogin}]");

          return ChatScreen(
            rideId: rideId,
            passengerName: passengerName,
            passengerImage: passengerImage,
          );
        },
      ),
    ],
    errorBuilder: (context, state) {
      print("Error Route: ${state.uri} [${currentTimestamp}] [${currentUserLogin}]");
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Route not found: ${state.uri}'),
              SizedBox(height: 16),
              Text(
                'Current Date and Time (UTC): $currentTimestamp',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                'Current User\'s Login: $currentUserLogin',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  context.go('/driver-check');
                },
                child: Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      );
    },
  );
});