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
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;
      final doc = await _db.collection('users').doc(uid).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return AppUser.fromMap(data); // <-- RENAMED
      } else {
        return null;
      }
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Sign out helper (used in main.dart).
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Fetch user profile by UID (used by main.dart per diagnostics).
  Future<AppUser?> getUserDetails(String uid) async { // <-- RENAMED
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

      final model = GenerativeModel(model: 'gemini-pro', apiKey: apiKey);
      print("--- 3. GenerativeModel initialized. ---");

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      print("--- 4. Received response from Gemini API. ---");

      return response.text ?? "Sorry, I received an empty response.";

    } catch (e, s) { 
      print("--- X. CATCH BLOCK ERROR ---");
      print("THE REAL ERROR IS: $e");
      print("STACK TRACE: $s");
      return 'An error occurred while trying to get a response. Please check your connection and API key.';
    }
  }

  // --------------------
  // Profile update
  // --------------------
  Future<void> updateUserProfile(String uid, Map<String, dynamic> updates) async {
    await _db.collection('users').doc(uid).update(updates);
  }
}