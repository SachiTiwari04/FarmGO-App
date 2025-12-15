// lib/firebase_services.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:farm_go_app/user_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FirebaseServices {
  // ----- core firebase clients -----
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ----- Gemini model instance (reused for performance) -----
  GenerativeModel? _geminiModel;

  // Initialize Gemini model once with CORRECT model name
  GenerativeModel _getGeminiModel() {
    if (_geminiModel == null) {
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('GEMINI_API_KEY not found in .env file');
      }
      _geminiModel = GenerativeModel(
        model: 'gemini-2.5-flash', // ✅ Using the latest available model
        apiKey: apiKey,
      );
    }
    return _geminiModel!;
  }

  // --------------------
  // Auth + profile methods
  // --------------------
  Future<AppUser?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String farmLocation,
    required String farmType,
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;
      final Map<String, dynamic> userMap = {
        'fullName': fullName,
        'farmLocation': farmLocation,
        'farmType': farmType,
        'email': email,
      };

      await _db.collection('users').doc(uid).set(userMap);
      return AppUser.fromMap(userMap);
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<AppUser?> logIn({
    required String email,
    required String password,
  }) async {
    try {
      print("--- LOGIN: Starting authentication for $email ---");
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print("--- LOGIN: Authentication successful, UID: ${userCredential.user!.uid} ---");
      final uid = userCredential.user!.uid;
      final doc = await _db.collection('users').doc(uid).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        print("--- LOGIN: User data retrieved successfully ---");
        return AppUser.fromMap(data);
      } else {
        print("--- LOGIN: User document does not exist, creating default user document ---");
        final Map<String, dynamic> defaultUserMap = {
          'fullName': 'User',
          'farmLocation': 'Not specified',
          'farmType': 'Poultry',
          'email': _auth.currentUser?.email ?? '',
        };
        
        await _db.collection('users').doc(uid).set(defaultUserMap);
        print("--- LOGIN: Default user document created ---");
        return AppUser.fromMap(defaultUserMap);
      }
    } on FirebaseAuthException catch (e) {
      print("--- LOGIN: FirebaseAuthException: ${e.code} - ${e.message} ---");
      rethrow;
    } catch (e) {
      print("--- LOGIN: General exception: $e ---");
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<AppUser?> getUserDetails(String uid) async {
    if (_auth.currentUser == null) {
      throw Exception('User not authenticated');
    }
    
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return AppUser.fromMap(data);
    }
    return null;
  }

  // --------------------
  // Checklist / farm / data helpers
  // --------------------
  Future<DocumentReference> saveChecklist(String uid, Map<String, dynamic> checklist) async {
    final ref = await _db.collection('users').doc(uid).collection('checklists').add({
      ...checklist,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  Future<DocumentReference> logFarmData(String uid, Map<String, dynamic> data) async {
    final ref = await _db.collection('users').doc(uid).collection('farmData').add({
      ...data,
      'timestamp': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  Stream<QuerySnapshot> getFarmDataStream(String uid) {
    return _db.collection('users').doc(uid).collection('farmData').orderBy('timestamp', descending: true).snapshots();
  }

  // --------------------
  // Locations
  // --------------------
  Stream<QuerySnapshot> getLocationsStream(String uid) {
    return _db.collection('users').doc(uid).collection('locations').snapshots();
  }

  Future<DocumentReference> addLocation(String uid, Map<String, dynamic> location) async {
    final ref = await _db.collection('users').doc(uid).collection('locations').add({
      ...location,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  // --------------------
  // Health records & image uploads
  // --------------------
  Future<String> uploadHealthRecordImage(dynamic fileOrBytes, String uid) async {
    final path = 'health_records/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child(path);

    UploadTask task;
    if (fileOrBytes is File) {
      task = ref.putFile(fileOrBytes);
    } else if (fileOrBytes is Uint8List) {
      task = ref.putData(fileOrBytes);
    } else {
      throw ArgumentError('uploadHealthRecordImage expects a File or Uint8List');
    }

    final snapshot = await task;
    final url = await snapshot.ref.getDownloadURL();
    return url;
  }

  Future<DocumentReference> saveHealthRecord(String uid, Map<String, dynamic> record) async {
    final ref = await _db.collection('users').doc(uid).collection('health_records').add({
      ...record,
      'timestamp': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  Stream<QuerySnapshot> getHealthRecordsStream(String uid) {
    return _db.collection('users').doc(uid).collection('health_records').orderBy('timestamp', descending: true).snapshots();
  }

  // --------------------
  // Image analysis
  // --------------------
  Future<String> analyzeFecalImage(dynamic fileOrBytes) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return 'Analysis indicates possible parasitic infection. Please consult a veterinarian for proper diagnosis.';
  }

  // --------------------
  // Chatbot (FIXED - Using google_generative_ai package)
  // --------------------
  Future<String> getChatbotResponse(String prompt) async {
    print("--- 1. getChatbotResponse called with prompt: $prompt ---");
    try {
      // Test connectivity first
      if (!await _hasInternetConnection()) {
        return 'Error: No internet connection. Please check your network and try again.';
      }
      
      final model = _getGeminiModel();
      print("--- 2. Gemini model initialized successfully ---");
      
      final content = [Content.text(prompt)];
      print("--- 3. Sending request to Gemini API ---");
      
      final response = await model.generateContent(content);
      print("--- 4. Response received successfully ---");
      
      return response.text ?? "Sorry, I received an empty response.";
      
    } catch (e, s) {
      print("--- ERROR in getChatbotResponse ---");
      print("Error: $e");
      print("Stack trace: $s");
      
      // Check if it's a DNS/network issue
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('No address associated with hostname')) {
        return 'Network Error: Unable to connect to AI service. Please check your internet connection and try restarting the app.';
      }
      
      return 'Error: Unable to get AI response. Please check your API key and try again.';
    }
  }

  // Helper method to check internet connectivity
  Future<bool> _hasInternetConnection() async {
    try {
      final result = await http.get(Uri.parse('https://www.google.com')).timeout(Duration(seconds: 5));
      return result.statusCode == 200;
    } catch (e) {
      print("Internet connectivity check failed: $e");
      return false;
    }
  }

  // --------------------
  // Profile update
  // --------------------
  Future<void> updateUserProfile(String uid, Map<String, dynamic> updates) async {
    await _db.collection('users').doc(uid).update(updates);
  }

  // --------------------
  // Testing methods
  // --------------------
  Future<void> testGeminiApiDirectly() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print("========== TEST: No API key found ==========");
      return;
    }

    print("========== TESTING GEMINI API ==========");
    print("API Key (first 10 chars): ${apiKey.substring(0, 10)}...");
    
    // First, try to list available models
    try {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print("✅ API Key is valid!");
        print("Available models:");
        for (var model in data['models']) {
          final name = model['name'].toString().replaceAll('models/', '');
          print("  - $name");
        }
      } else {
        print("❌ API Key validation failed!");
        print("Status: ${response.statusCode}");
        print("Response: ${response.body}");
      }
    } catch (e) {
      print("❌ Failed to list models: $e");
    }

    // Now try with available model names from your API
    final modelsToTry = [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
      'gemini-flash-latest',
      'gemini-pro-latest',
    ];

    for (var modelName in modelsToTry) {
      try {
        print("\nTrying model: $modelName");
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey
        );
        final content = [Content.text("Hello")];
        final response = await model.generateContent(content);
        
        print("✅ SUCCESS with $modelName!");
        print("Response: ${response.text}");
        print("========================================");
        return; // Exit after first success
      } catch (e) {
        print("❌ Failed with $modelName: $e");
      }
    }
    
    print("========================================");
  }
  
}