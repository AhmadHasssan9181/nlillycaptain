// lib/main.dart - Modified for Captain (Driver) app
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:lilycaptain/providers/emergency_sos_provider.dart';
import 'package:lilycaptain/widgets/sos_overlay.dart';
import 'package:lilycaptain/services/permission_service.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Request permissions early
  try {
    await PermissionService.requestVibratePermission();
    await PermissionService.requestCallPermission();
  } catch (e) {
    print("Error requesting permissions: $e");
  }

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize the SOS service when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(emergencySosProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final primaryColor = Colors.pink[400];
    final sosState = ref.watch(emergencySosProvider);

    return MaterialApp.router(
      title: 'Lily Captain',
      theme: ThemeData(
        primaryColor: primaryColor,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: primaryColor,
          secondary: Colors.pinkAccent,
        ),
      ),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) {
        // Wrap the entire app with the SOS overlay
        return Stack(
          children: [
            child!,
            if (sosState.isActivated) const SOSOverlay(),
          ],
        );
      },
    );
  }
}

// Add this if you want a way to test the SOS functionality from anywhere
class SosTestButton extends ConsumerWidget {
  const SosTestButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton(
      backgroundColor: Colors.red,
      child: const Icon(Icons.warning_amber_rounded),
      onPressed: () {
        ref.read(emergencySosProvider.notifier).triggerTestCrash();
      },
    );
  }
}



