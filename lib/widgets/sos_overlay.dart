import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/emergency_sos_provider.dart';

class SOSOverlay extends ConsumerStatefulWidget {
  const SOSOverlay({Key? key}) : super(key: key);

  @override
  ConsumerState<SOSOverlay> createState() => _SOSOverlayState();
}

class _SOSOverlayState extends ConsumerState<SOSOverlay> {
  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(emergencySosProvider);
    final countdownSeconds = sosState.countdownSeconds;

    return Container(
      color: Colors.red.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emergency,
              color: Colors.white,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'EMERGENCY MODE ACTIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (countdownSeconds != null && countdownSeconds > 0)
              Text(
                'Calling emergency in $countdownSeconds seconds',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              )
            else
              const Text(
                'Help is on the way',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                print("CANCEL BUTTON PRESSED");

                // First, access the service directly through the provider
                final service = ref.read(emergencySosServiceProvider);
                if (service != null) {
                  print("Cancelling SOS through service directly");
                  service.cancelSosSequence();
                }

                // Then update the provider state
                ref.read(emergencySosProvider.notifier).deactivateSOS();

                // Force rebuild
                if (mounted) {
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('CANCEL EMERGENCY'),
            ),
          ],
        ),
      ),
    );
  }
}