import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  // List of all required permissions
  static const List<Permission> _requiredPermissions = [
    Permission.location,
    Permission.locationAlways,
    Permission.locationWhenInUse,
  ];

  // Check if we have all required permissions
  static Future<bool> hasRequiredPermissions() async {
    try {
      // Check location permission status
      final locationStatus = await Permission.location.status;
      
      // For Android 10 and above, we need to check background location too
      if (await _isAndroid10OrAbove()) {
        final backgroundLocationStatus = await Permission.locationAlways.status;
        return locationStatus.isGranted && backgroundLocationStatus.isGranted;
      }
      
      return locationStatus.isGranted;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    }
  }

  // Request all required permissions
  static Future<bool> requestPermissions() async {
    try {
      // Request location permissions
      final statuses = await _requiredPermissions.request();
      
      // Check if all permissions are granted
      return statuses.values.every((status) => status.isGranted);
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  // Open app settings so user can manually enable permissions
  static Future<bool> openAppSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      debugPrint('Error opening app settings: $e');
      return false;
    }
  }

  // Check if the device is running Android 10 or above
  static Future<bool> _isAndroid10OrAbove() async {
    if (!Platform.isAndroid) return false;
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt >= 29; // Android 10 is API level 29
    } catch (e) {
      debugPrint('Error checking Android version: $e');
      return false;
    }
  }
}
