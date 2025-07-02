import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class PermissionService {
  // Check and request all required permissions at app startup
  // Fix in requestAppPermissions
  static Future<Map<Permission, PermissionStatus>> requestAppPermissions(BuildContext context) async {
    final permissions = [
      Permission.locationWhenInUse,
      Permission.contacts,
      Permission.phone,
    ];

    Map<Permission, PermissionStatus> statuses = await permissions.request();

    statuses.forEach((permission, status) {
      if (status.isDenied && context.mounted) {
        _showPermissionExplanation(context, permission);
      } else if (status.isPermanentlyDenied && context.mounted) {
        _showSettingsDialog(context, permission);
      }
    });

    return statuses;
  }

// Add the new method
  static Future<PermissionStatus> requestVibratePermission() async {
   return PermissionStatus.granted;  // Using vibration not vibrate
  }
  // Request location permissions with proper rationale
  static Future<PermissionStatus> requestLocationPermission(BuildContext context) async {
    PermissionStatus status = await Permission.locationWhenInUse.status;

    if (status.isGranted) {
      return status;
    }

    if (status.isRestricted || status.isDenied) {
      if (context.mounted) {
        final shouldRequest = await _showPermissionRationale(
          context,
          'Location Access',
          'Lily Drive needs your location to show nearby services and provide accurate navigation.',
          'For the best experience, please grant location access when prompted.',
        );

        if (shouldRequest) {
          status = await Permission.locationWhenInUse.request();
        }
      }
    }

    if (status.isPermanentlyDenied && context.mounted) {
      _showSettingsDialog(context, Permission.locationWhenInUse);
    }

    return status;
  }

  // Get the current location of the user
  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null; // Location services are not enabled
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null; // Permissions are denied
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null; // Permissions are denied forever
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  static void _showPermissionExplanation(BuildContext context, Permission permission) {
    String title = 'Permission Required';
    String content = 'This feature requires additional permissions to work properly.';

    if (permission == Permission.locationWhenInUse) {
      title = 'Location Permission Required';
      content = 'Lily Drive needs location permission to help you navigate and find rides near you.';
    } else if (permission == Permission.contacts) {
      title = 'Contacts Permission Required';
      content = 'Lily Drive needs contacts permission to help you easily share rides with friends.';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              permission.request();
            },
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  static void _showSettingsDialog(BuildContext context, Permission permission) {
    String permissionName = 'this permission';

    if (permission == Permission.locationWhenInUse) {
      permissionName = 'location permission';
    } else if (permission == Permission.contacts) {
      permissionName = 'contacts permission';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(
          'We need $permissionName for essential app features to work. '
              'Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _showPermissionRationale(
      BuildContext context,
      String title,
      String message,
      String details,
      ) async {
    bool shouldRequest = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Text(
              details,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              shouldRequest = false;
              Navigator.pop(context);
            },
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () {
              shouldRequest = true;
              Navigator.pop(context);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return shouldRequest;
  }

  static Future<bool> requestCallPermission() async {
    // Request phone call permission
    try {
      var status = await Permission.phone.status;
      if (!status.isGranted) {
        status = await Permission.phone.request();
      }
      return status.isGranted;
    } catch (e) {
      print("Error requesting call permission: $e");
      return false;
    }
  }
}