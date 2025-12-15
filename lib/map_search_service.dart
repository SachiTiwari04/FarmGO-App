// lib/map_search_service.dart - REPLACE YOUR EXISTING FILE
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:farm_go_app/location_service.dart';

class SearchResult {
  final String id;
  final String name;
  final String description;
  final LatLng coordinates;
  final String type; // 'local', 'google_places'
  final Map<String, dynamic>? additionalData;

  SearchResult({
    required this.id,
    required this.name,
    required this.description,
    required this.coordinates,
    required this.type,
    this.additionalData,
  });
}

class MapSearchService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _locationService = LocationService(); // Use singleton location service
  
  // Google Places API key from .env file
  String? get _placesApiKey => dotenv.env['GOOGLE_PLACES_API_KEY'];
  
  // Search history storage
  List<SearchResult> _searchHistory = [];
  List<SearchResult> _favorites = [];
  
  // Caching for performance
  final Map<String, List<SearchResult>> _searchCache = {};
  final Map<String, List<SearchResult>> _localCache = {};
  DateTime? _localCacheTime;
  
  // Debouncing
  Timer? _debounceTimer;

  // Get current user's farm locations with caching
  Future<List<SearchResult>> _searchLocalLocations(String query) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final cacheKey = 'local_${user.uid}';
    final now = DateTime.now();
    
    // Check if we have cached data that's less than 5 minutes old
    if (_localCache.containsKey(cacheKey) && 
        _localCacheTime != null && 
        now.difference(_localCacheTime!).inMinutes < 5) {
      
      // Filter cached results
      return _localCache[cacheKey]!
          .where((result) =>
              result.name.toLowerCase().contains(query.toLowerCase()) ||
              result.description.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }

    try {
      final snapshot = await _db
          .collection('users')
          .doc(user.uid)
          .collection('locations')
          .get();

      final allResults = <SearchResult>[];
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String;
        final type = data['type'] as String;
        final geoPoint = data['coordinates'] as GeoPoint;
        
        allResults.add(SearchResult(
          id: doc.id,
          name: name,
          description: 'Farm Location - $type',
          coordinates: LatLng(geoPoint.latitude, geoPoint.longitude),
          type: 'local',
          additionalData: data,
        ));
      }
      
      // Cache all results
      _localCache[cacheKey] = allResults;
      _localCacheTime = now;
      
      // Filter and return matching results
      return allResults
          .where((result) =>
              result.name.toLowerCase().contains(query.toLowerCase()) ||
              result.description.toLowerCase().contains(query.toLowerCase()))
          .toList();
      
    } catch (e) {
      print('Error searching local locations: $e');
      return [];
    }
  }

  // Search Google Places with caching
  Future<List<SearchResult>> _searchGooglePlaces(String query) async {
    if (query.length < 3) return []; // Avoid too many API calls
    
    // Check cache first
    final cacheKey = query.toLowerCase().trim();
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }
    
    final apiKey = _placesApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      print('Google Places API key not found in .env file');
      return [];
    }
    
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&types=establishment|geocode'
        '&key=$apiKey'
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = data['predictions'] as List;
        
        final results = <SearchResult>[];
        
        // Process only first 3 results for speed
        for (final prediction in predictions.take(3)) {
          final placeId = prediction['place_id'] as String;
          final name = prediction['structured_formatting']['main_text'] as String;
          final description = prediction['description'] as String;
          
          // Get place details for coordinates
          final coordinates = await _getPlaceCoordinates(placeId);
          if (coordinates != null) {
            results.add(SearchResult(
              id: placeId,
              name: name,
              description: description,
              coordinates: coordinates,
              type: 'google_places',
              additionalData: prediction,
            ));
          }
        }
        
        // Cache the results
        _searchCache[cacheKey] = results;
        
        // Limit cache size to prevent memory issues
        if (_searchCache.length > 50) {
          final firstKey = _searchCache.keys.first;
          _searchCache.remove(firstKey);
        }
        
        return results;
      }
    } catch (e) {
      print('Error searching Google Places: $e');
    }
    
    return [];
  }

  // Get coordinates for a specific place
  Future<LatLng?> _getPlaceCoordinates(String placeId) async {
    final apiKey = _placesApiKey;
    if (apiKey == null || apiKey.isEmpty) return null;
    
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=geometry'
        '&key=$apiKey'
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geometry = data['result']['geometry']['location'];
        return LatLng(geometry['lat'], geometry['lng']);
      }
    } catch (e) {
      print('Error getting place coordinates: $e');
    }
    
    return null;
  }

  // Debounced search function
  Future<List<SearchResult>> searchWithDebounce(
    String query, 
    Function(List<SearchResult>) onResults,
    {Duration delay = const Duration(milliseconds: 300)}
  ) async {
    _debounceTimer?.cancel();
    
    _debounceTimer = Timer(delay, () async {
      final results = await search(query);
      onResults(results);
    });
    
    return [];
  }

  // Main search function (hybrid approach) - optimized
  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final results = <SearchResult>[];
    
    // 1. Search local farm locations first (fast)
    final localResults = await _searchLocalLocations(query);
    results.addAll(localResults);
    
    // 2. Only search Google Places if:
    //    - We have few local results AND
    //    - Query is long enough to be meaningful
    if (localResults.length < 2 && query.length >= 4) {
      final googleResults = await _searchGooglePlaces(query);
      results.addAll(googleResults);
    }
    
    return results;
  }

  // Add to search history
  void addToHistory(SearchResult result) {
    _searchHistory.removeWhere((item) => item.id == result.id);
    _searchHistory.insert(0, result);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.take(10).toList();
    }
  }

  // Add to favorites
  void addToFavorites(SearchResult result) {
    if (!_favorites.any((item) => item.id == result.id)) {
      _favorites.add(result);
    }
  }

  // Remove from favorites
  void removeFromFavorites(String id) {
    _favorites.removeWhere((item) => item.id == id);
  }

  // Get search history
  List<SearchResult> getSearchHistory() => List.from(_searchHistory);

  // Get favorites
  List<SearchResult> getFavorites() => List.from(_favorites);

  // Get current location using the singleton LocationService
  Future<LatLng?> getCurrentLocation() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null) {
      return LatLng(position.latitude, position.longitude);
    }
    return null;
  }
  
  // Clear location cache when needed
  void clearLocationCache() {
    _locationService.clearCache();
  }
}