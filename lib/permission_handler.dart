import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// This function requests camera and location permissions
Future<bool> requestPermissions() async {
  // Use 'final', not 'const', for lists with non-constant values
  final permissions = [
    Permission.camera,
    Permission.locationWhenInUse,
  ];

  Map<Permission, PermissionStatus> statuses = await permissions.request();

  // Check if both permissions are granted
  bool isGranted = statuses[Permission.camera] == PermissionStatus.granted &&
      statuses[Permission.locationWhenInUse] == PermissionStatus.granted;

  return isGranted;
}

// This function can be called if permissions are permanently denied
void handlePermissionsAndNavigate(BuildContext context, {bool shouldNavigate = true}) {
  showDialog(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text("Permissions Required"),
      content: const Text("This app needs camera and location access to function properly. Please grant permissions in app settings."),
      actions: <Widget>[
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: const Text("Open Settings"),
          onPressed: () {
            openAppSettings(); // This function is from the permission_handler package
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}