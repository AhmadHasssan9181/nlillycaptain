import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/emergency_sos_service.dart';

class EmergencySosState {
  final bool isActivated;
  final DateTime? activatedAt;
  final int? countdownSeconds;

  EmergencySosState({
    this.isActivated = false,
    this.activatedAt,
    this.countdownSeconds,
  });

  EmergencySosState copyWith({
    bool? isActivated,
    DateTime? activatedAt,
    int? countdownSeconds,
  }) {
    return EmergencySosState(
      isActivated: isActivated ?? this.isActivated,
      activatedAt: activatedAt ?? this.activatedAt,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    );
  }
}

// Use StateProvider to allow updates to the service
final emergencySosServiceProvider = StateProvider<EmergencySosService?>((ref) {
  return null; // Initially null, will be set by HomeScreen
});

class EmergencySosNotifier extends StateNotifier<EmergencySosState> {
  final Ref _ref;

  EmergencySosNotifier(this._ref) : super(EmergencySosState());

  void initialize() {
    // No longer creating a new service here
    print("EmergencySosNotifier initialized");
  }

  void activateSOS() {
    state = state.copyWith(
      isActivated: true,
      activatedAt: DateTime.now(),
    );
    print("SOS activated in provider at ${state.activatedAt}");
  }

  void deactivateSOS() {
    state = state.copyWith(isActivated: false);
    print("SOS deactivated in provider");

    // Access the service through the provider
    final service = _ref.read(emergencySosServiceProvider);
    if (service != null && service.isSosActive) {
      service.cancelSosSequence();
      print("Provider: Cancellation sent to service");
    }
  }

  void updateCountdown(int seconds) {
    state = state.copyWith(countdownSeconds: seconds);
  }

  // Add this method to fix the triggerTestCrash error
  void triggerTestCrash() {
    final service = _ref.read(emergencySosServiceProvider);
    if (service != null) {
      service.triggerTestCrash();
      print("Test crash triggered from provider");
    } else {
      print("Cannot trigger test crash - service not initialized");
    }
  }
}

final emergencySosProvider = StateNotifierProvider<EmergencySosNotifier, EmergencySosState>(
      (ref) => EmergencySosNotifier(ref),
);