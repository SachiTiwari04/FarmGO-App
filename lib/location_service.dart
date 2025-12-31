// lib/location_service.dart 
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Position? _lastPosition;
  DateTime? _lastUpdate;
  static const _cacheDuration = Duration(minutes: 5);

  // Get location with caching to avoid excessive calls
  Future<Position?> getCurrentLocation() async {
    // Return cached position if still valid
    if (_lastPosition != null && 
        _lastUpdate != null && 
        DateTime.now().difference(_lastUpdate!) < _cacheDuration) {
      print('--- LOCATION: Using cached position ---');
      return _lastPosition;
    }

    try {
      print('--- LOCATION: Checking permissions ---');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('--- LOCATION: Location services are disabled ---');
        return null;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('--- LOCATION: Location permissions are denied ---');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('--- LOCATION: Location permissions are permanently denied ---');
        return null;
      }

      print('--- LOCATION: Getting current position ---');
      
      // Get position with timeout
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Cache the position
      _lastPosition = position;
      _lastUpdate = DateTime.now();
      
      print('--- LOCATION: Position retrieved successfully ---');
      return position;
      
    } catch (e) {
      print('--- LOCATION ERROR: $e ---');
      return _lastPosition; // Return last known position on error
    }
  }

  // Clear cache when needed
  void clearCache() {
    _lastPosition = null;
    _lastUpdate = null;
  }
}