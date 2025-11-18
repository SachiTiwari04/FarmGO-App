// lib/firebase_services.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:farm_go_app/user_model.dart'; // This now imports AppUser

// ADDED for Gemini API
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class FirebaseServices {
  // ----- core firebase clients -----
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // --------------------
  // Auth + profile methods
  // --------------------

  /// Create auth user, write profile doc and return an AppUser object.
  Future<AppUser?> signUp({ // <-- RENAMED
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

      return AppUser.fromMap(userMap); // <-- RENAMED
    } on FirebaseAuthException {
      rethrow; 
    } catch (e) {
      rethrow;
    }
  }

  /// Sign in and fetch profile doc by uid.
  Future<AppUser?> logIn({ // <-- RENAMED
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
        return AppUser.fromMap(data); // <-- RENAMED
      } else {
        print("--- LOGIN: User document does not exist, creating default user document ---");
        // Create a default user document for existing authenticated users
        final Map<String, dynamic> defaultUserMap = {
          'fullName': 'User', // Default name
          'farmLocation': 'Not specified',
          'farmType': 'Poultry', // Default farm type
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

  /// Sign out helper (used in main.dart).
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Fetch user profile by UID (used by main.dart per diagnostics).
  Future<AppUser?> getUserDetails(String uid) async { // <-- RENAMED
    // Check if user is authenticated
    if (_auth.currentUser == null) {
      throw Exception('User not authenticated');
    }
    
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return AppUser.fromMap(data); // <-- RENAMED
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
  // Image analysis / ML placeholders
  // --------------------
  Future<String> analyzeFecalImage(dynamic fileOrBytes) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return 'Analysis indicates possible parasitic infection. Please consult a veterinarian for proper diagnosis.';
  }

  // --------------------
  // Chatbot (NOW POWERED BY GEMINI)
  // --------------------
 Future<String> getChatbotResponse(String prompt) async {
  print("--- 1. getChatbotResponse called with prompt: $prompt ---");
  try {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    
    if (apiKey == null || apiKey.isEmpty) {
      print("--- 2. ERROR: API key is null or empty. ---");
      return 'Error: API Key is missing from .env file.';
    }
    
    print("--- 2. API Key loaded successfully. ---");

    // Use the correct model name from the available list
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=$apiKey'
    );
    
    print("--- 3. Making HTTP request to Gemini API ---");

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
    );

    print("--- 4. Response received. Status: ${response.statusCode} ---");

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
      return text ?? "Sorry, I received an empty response.";
    } else {
      print("--- ERROR: ${response.body} ---");
      return 'Error: Unable to get response from AI. Status: ${response.statusCode}';
    }

  } catch (e, s) { 
    print("--- X. CATCH BLOCK ERROR ---");
    print("THE REAL ERROR IS: $e");
    print("STACK TRACE: $s");
    return 'An error occurred: $e';
  }
}
  // --------------------
  // Profile update
  // --------------------
  Future<void> updateUserProfile(String uid, Map<String, dynamic> updates) async {
    await _db.collection('users').doc(uid).update(updates);
  }
  // Add this method to test which models are available
Future<void> listAvailableModels() async {
  try {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print("No API key found");
      return;
    }

    // Try to list models using the API directly
    print("--- Attempting to list available models ---");
    
    // Try the simplest model name first
    final model = GenerativeModel(model: 'models/gemini-pro', apiKey: apiKey);
    final content = [Content.text("Hello")];
    final response = await model.generateContent(content);
    print("SUCCESS with models/gemini-pro: ${response.text}");
    
  } catch (e) {
    print("Error listing models: $e");
  }
}
Future<void> testGeminiApiDirectly() async {
  final apiKey = dotenv.env['GEMINI_API_KEY'];
  if (apiKey == null) {
    print("No API key");
    return;
  }

  try {
    // List available models
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models?key=$apiKey'
    );
    
    final response = await http.get(url);

    print("========== LISTING AVAILABLE MODELS ==========");
    print("Status Code: ${response.statusCode}");
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final models = data['models'] as List;
      
      print("Available models:");
      for (var model in models) {
        print("  - ${model['name']}");
      }
    } else {
      print("Error: ${response.body}");
    }
    print("==============================================");
    
  } catch (e) {
    print("========== ERROR LISTING MODELS ==========");
    print("Error: $e");
    print("==========================================");
  }
}

}