import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'permission_service.dart';

class EmergencySosService {
  // Adjusted thresholds for more realistic crash detection
  static const double ACCELERATION_THRESHOLD = 25.0; // Increased from 15.0 - more severe impact needed
  static const double GYROSCOPE_THRESHOLD = 15.0; // Increased from 10.0 - more severe rotation needed
  static const String EMERGENCY_NUMBER = '1122'; // Pakistan rescue service

  // Enhanced detection parameters
  static const int DETECTION_WINDOW_MS = 2000; // 2 second window for sustained impact
  static const int MIN_DETECTION_COUNT = 3; // Minimum detections within window
  static const double GRAVITY = 9.81; // Standard gravity for reference

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Disable audio completely by setting this to false
  bool _audioEnabled = false; // Set to false to disable audio completely

  // Sensor subscriptions
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  // State variables
  bool _isMonitoring = false;
  bool _sosActivated = false;
  Timer? _sosCountdownTimer;
  Timer? _vibrationTimer;
  int _countdownSeconds = 10;
  bool _vibrationActive = false;

  // Enhanced crash detection variables
  List<DateTime> _recentDetections = [];
  DateTime? _lastSensorReading;
  bool _deviceIsStationary = true;
  Timer? _stationaryTimer;

  // Callbacks
  final VoidCallback? onCrashDetected;
  final VoidCallback? onSosActivated;
  final VoidCallback? onSosCancelled;
  final ValueChanged<int>? onCountdownTick;

  EmergencySosService({
    this.onCrashDetected,
    this.onSosActivated,
    this.onSosCancelled,
    this.onCountdownTick,
  }) {
    // Load alarm sound
    _initAudioPlayer();
  }

  // Initialize the audio player
  Future<void> _initAudioPlayer() async {
    try {
      await _audioPlayer.setAsset('assets/sounds/tununounnon.mp3');
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.setVolume(0.0); // Start with volume at 0
      print("Audio player initialized successfully");
    } catch (e) {
      print("Error initializing audio player: $e");
    }
  }

  bool get isMonitoring => _isMonitoring;
  bool get isSosActive => _sosActivated;
  int get remainingSeconds => _countdownSeconds;

  // Start monitoring sensors with enhanced detection
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _recentDetections.clear();
    _deviceIsStationary = true;

    try {
      // Monitor accelerometer with enhanced logic
      _accelerometerSubscription = accelerometerEvents.listen(
            (event) {
          _updateStationaryStatus();
          final magnitude = _calculateAccelerationMagnitude(event.x, event.y, event.z);

          // Only check for crashes if device was recently stationary (likely in a vehicle)
          if (_shouldCheckForCrash(magnitude)) {
            _recordDetection();
            if (_isPossibleCrash()) {
              _detectPossibleCrash();
            }
          }
        },
        onError: (error) {
          print("Accelerometer error: $error");
        },
      );

      // Monitor gyroscope for sudden rotations
      _gyroscopeSubscription = gyroscopeEvents.listen(
            (event) {
          final magnitude = _calculateMagnitude(event.x, event.y, event.z);
          if (magnitude > GYROSCOPE_THRESHOLD && _deviceIsStationary) {
            _recordDetection();
            if (_isPossibleCrash()) {
              _detectPossibleCrash();
            }
          }
        },
        onError: (error) {
          print("Gyroscope error: $error");
        },
      );

      // Monitor magnetometer for additional context
      _magnetometerSubscription = magnetometerEvents.listen(
            (event) {
          // Could be used to enhance crash detection algorithm
          // For now, just used for context
        },
        onError: (error) {
          print("Magnetometer error: $error");
        },
      );

      print("Enhanced sensor monitoring started");
    } catch (e) {
      print("Error starting sensor monitoring: $e");
      _isMonitoring = false;
    }
  }

  // Calculate acceleration magnitude accounting for gravity
  double _calculateAccelerationMagnitude(double x, double y, double z) {
    final totalMagnitude = sqrt(x * x + y * y + z * z);
    // Subtract gravity to get net acceleration
    return (totalMagnitude - GRAVITY).abs();
  }

  // Calculate general vector magnitude
  double _calculateMagnitude(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  // Update device stationary status
  void _updateStationaryStatus() {
    _lastSensorReading = DateTime.now();

    // Reset stationary timer
    _stationaryTimer?.cancel();
    _stationaryTimer = Timer(const Duration(seconds: 5), () {
      _deviceIsStationary = true;
      print("Device marked as stationary");
    });

    if (_deviceIsStationary) {
      _deviceIsStationary = false;
      print("Device is moving");
    }
  }

  // Check if we should evaluate this reading for crash detection
  bool _shouldCheckForCrash(double magnitude) {
    return magnitude > ACCELERATION_THRESHOLD;
  }

  // Record a potential crash detection
  void _recordDetection() {
    final now = DateTime.now();
    _recentDetections.add(now);

    // Clean up old detections outside the window
    _recentDetections.removeWhere((detection) {
      return now.difference(detection).inMilliseconds > DETECTION_WINDOW_MS;
    });
  }

  // Check if recent detections constitute a possible crash
  bool _isPossibleCrash() {
    // Need multiple detections within the time window
    if (_recentDetections.length >= MIN_DETECTION_COUNT) {
      print("Multiple severe impacts detected: ${_recentDetections.length}");
      return true;
    }
    return false;
  }

  // Enhanced crash detection with false positive reduction
  void _detectPossibleCrash() {
    if (_sosActivated) return;

    // Additional validation
    final now = DateTime.now();
    final recentDetectionCount = _recentDetections.where((detection) {
      return now.difference(detection).inMilliseconds <= DETECTION_WINDOW_MS;
    }).length;

    if (recentDetectionCount >= MIN_DETECTION_COUNT) {
      print("CRASH DETECTED - Multiple severe impacts: $recentDetectionCount");
      print("Recent detections: ${_recentDetections.map((d) => d.millisecondsSinceEpoch).toList()}");

      // Clear detections to prevent multiple triggers
      _recentDetections.clear();

      onCrashDetected?.call();
      activateSosSequence();
    } else {
      print("Single impact detected but not enough for crash confirmation");
    }
  }

  // Activate SOS countdown sequence
  void activateSosSequence() {
    if (_sosActivated) {
      print("SOS already activated");
      return;
    }

    print("SOS SEQUENCE ACTIVATED");
    _sosActivated = true;
    _countdownSeconds = 10;
    onSosActivated?.call();

    // Start alarm sound
    _playAlarmSound();

    // Start vibration pattern
    _startVibration();

    // Start countdown timer
    _sosCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownSeconds--;
      print("SOS COUNTDOWN: $_countdownSeconds");
      onCountdownTick?.call(_countdownSeconds);

      if (_countdownSeconds <= 0) {
        timer.cancel();
        _sosCountdownTimer = null;
        print("COUNTDOWN FINISHED - CALLING EMERGENCY NUMBER");
        _makeEmergencyCall();
      }
    });
  }

  // Play alarm sound with error handling
  void _playAlarmSound() {
    if (!_audioEnabled) {
      print("Audio is disabled");
      return;
    }

    try {
      _audioPlayer.setVolume(1.0).then((_) {
        _audioPlayer.play().catchError((error) {
          print("Error playing audio: $error");
        });
      });
    } catch (e) {
      print("Audio play exception: $e");
    }
  }

  // Start vibration pattern using vibration package
  void _startVibration() async {
    try {
      // First check if vibration is supported
      bool? hasVibrator = false;
      try {
        await PermissionService.requestVibratePermission();
        hasVibrator = await Vibration.hasVibrator();
        print("Has vibrator: $hasVibrator");
      } catch (e) {
        print("Error checking vibration capability: $e");
        hasVibrator = false;
      }

      if (hasVibrator == true) {
        _stopVibration(); // Stop any existing vibration first

        // Set a flag to track if vibration is active
        _vibrationActive = true;

        // Create SOS pattern (... --- ...)
        // Short pulses followed by long pulses followed by short pulses
        final List<int> sosPattern = [
          300, 100, 300, 100, 300, 100,  // ... (3 short)
          500, 100, 500, 100, 500, 100,  // --- (3 long)
          300, 100, 300, 100, 300, 100,  // ... (3 short)
        ];

        _vibrationTimer = Timer.periodic(const Duration(milliseconds: 3000), (timer) {
          if (!_vibrationActive) {
            timer.cancel();
            return;
          }

          try {
            // Check if pattern vibration is supported
            Vibration.hasCustomVibrationsSupport().then((hasCustomVibration) {
              if (hasCustomVibration == true) {
                // Use pattern vibration
                Vibration.vibrate(pattern: sosPattern, repeat: 0);
              } else {
                // Fallback to simple vibration
                Vibration.vibrate(duration: 1000);
              }
            });
          } catch (e) {
            print("Vibration error: $e");
            // Don't keep trying if we get permission errors
            if (e.toString().contains("permission")) {
              timer.cancel();
              _vibrationActive = false;
              print("Stopping vibration due to permission error");
            }
          }
        });
      }
    } catch (e) {
      print("Vibration setup error: $e");
      _vibrationActive = false;
    }
  }

  // Stop vibration properly
  void _stopVibration() {
    try {
      // Cancel the timer that triggers vibrations
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      _vibrationActive = false;

      // Stop any active vibration
      Vibration.cancel();

      print("Vibration stopped");
    } catch (e) {
      print("Error stopping vibration: $e");
    }
  }

  // Enhanced cancelSosSequence method
  void cancelSosSequence() {
    print("CANCEL SOS REQUESTED");
    if (!_sosActivated) {
      print("SOS not active, nothing to cancel");
      return;
    }

    print("CANCELLING ACTIVE SOS");
    _sosActivated = false;

    // Cancel countdown timer
    if (_sosCountdownTimer != null) {
      _sosCountdownTimer!.cancel();
      _sosCountdownTimer = null;
      print("Countdown timer cancelled");
    }

    // Stop audio with multiple safeguards
    _stopAudioCompletely();

    // Stop vibration
    _stopVibration();

    // Clear recent detections
    _recentDetections.clear();

    // Notify listeners that SOS was cancelled
    onSosCancelled?.call();
    print("SOS cancelled successfully");
  }

  // Completely stop audio with multiple approaches
  void _stopAudioCompletely() {
    try {
      // Try multiple methods to ensure audio stops
      _audioPlayer.stop().then((_) {
        _audioPlayer.pause().then((_) {
          _audioPlayer.setVolume(0).then((_) {
            print("Audio stopped with multiple methods");
          });
        });
      }).catchError((e) {
        print("Error in audio stop sequence: $e");
        // Try one more approach - recreate the player
        _resetAudioPlayer();
      });
    } catch (e) {
      print("Error stopping audio: $e");
      _resetAudioPlayer();
    }
  }

  // Reset audio player as last resort (instead of recreating it)
  Future<void> _resetAudioPlayer() async {
    try {
      // Instead of creating a new instance (which isn't possible with final),
      // reset the existing one
      await _audioPlayer.stop();
      await _audioPlayer.pause();
      await _audioPlayer.setVolume(0);
      await _audioPlayer.seek(Duration.zero);

      // Re-initialize with silence
      await _initAudioPlayer();
      print("Audio player reset");
    } catch (e) {
      print("Error resetting audio player: $e");
    }
  }

  // Make emergency call
  void _makeEmergencyCall() async {
    print("INITIATING EMERGENCY CALL TO: $EMERGENCY_NUMBER");
    final Uri telUri = Uri(scheme: 'tel', path: EMERGENCY_NUMBER);

    try {
      bool canLaunch = await canLaunchUrl(telUri);
      print("Can launch call: $canLaunch");

      if (canLaunch) {
        await launchUrl(telUri);
        print("Emergency call launched");
        // Stop SOS sequence after making the call
        cancelSosSequence();
      } else {
        print("Cannot launch emergency call - trying alternative method");
        await launchUrl(telUri);
      }
    } catch (e) {
      print("Error making emergency call: $e");
    }
  }

  // Stop monitoring sensors
  void stopMonitoring() {
    print("Stopping sensor monitoring");
    _isMonitoring = false;

    try {
      _accelerometerSubscription?.cancel();
      _accelerometerSubscription = null;

      _gyroscopeSubscription?.cancel();
      _gyroscopeSubscription = null;

      _magnetometerSubscription?.cancel();
      _magnetometerSubscription = null;

      _stationaryTimer?.cancel();
      _stationaryTimer = null;

      // Clear detection history
      _recentDetections.clear();

      print("Sensor monitoring stopped");
    } catch (e) {
      print("Error stopping sensor monitoring: $e");
    }
  }

  // Clean up resources
  void dispose() {
    print("Disposing EmergencySosService");
    stopMonitoring();
    cancelSosSequence();

    try {
      _sosCountdownTimer?.cancel();
      _vibrationTimer?.cancel();
      _stationaryTimer?.cancel();
      _audioPlayer.dispose();
      print("EmergencySosService disposed successfully");
    } catch (e) {
      print("Error during disposal: $e");
    }
  }

  // Manual trigger for testing (add this method for debugging)
  void triggerTestCrash() {
    print("MANUAL TEST CRASH TRIGGERED");
    onCrashDetected?.call();
    activateSosSequence();
  }
}