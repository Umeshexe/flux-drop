import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Signs in anonymously and ensures a UserModel exists in Firestore.
  Future<UserModel> signInAnonymously() async {
    debugPrint('🔐 [Auth] Signing in anonymously...');
    UserCredential cred = await _auth.signInAnonymously();
    final uid = cred.user!.uid;
    debugPrint('🔐 [Auth] Signed in. UID: $uid');
    return _ensureUserModel(uid);
  }

  /// Fetches the UserModel for the currently signed-in user.
  Future<UserModel?> getCurrentUserModel() async {
    final uid = currentUser?.uid;
    debugPrint('🔐 [Auth] getCurrentUserModel — uid: $uid');
    if (uid == null) return null;
    final doc = await _db.collection(AppConstants.usersCollection).doc(uid).get();
    if (!doc.exists) {
      debugPrint('🔐 [Auth] No user doc found in Firestore');
      return null;
    }
    final model = UserModel.fromMap(doc.data()!);
    debugPrint('🔐 [Auth] Restored user: ${model.shortCode}');
    return model;
  }

  /// Ensures a UserModel is created in Firestore, with a unique short code.
  Future<UserModel> _ensureUserModel(String uid) async {
    debugPrint('👤 [Auth] Ensuring user model for uid: $uid');
    final docRef = _db.collection(AppConstants.usersCollection).doc(uid);
    final doc = await docRef.get();
    if (doc.exists) {
      final model = UserModel.fromMap(doc.data()!);
      debugPrint('👤 [Auth] Existing user found: ${model.shortCode}');
      await _updateFcmToken(uid);
      return model;
    }

    debugPrint('👤 [Auth] No user doc found — creating new one...');
    final shortCode = await _generateUniqueShortCode();
    debugPrint('👤 [Auth] Generated short code: $shortCode');

    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('📲 [FCM] Token obtained: ${fcmToken?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('📲 [FCM] Token fetch failed: $e');
      fcmToken = null;
    }

    final model = UserModel(
      uid: uid,
      shortCode: shortCode,
      createdAt: DateTime.now(),
      fcmToken: fcmToken,
    );

    await docRef.set(model.toMap());
    debugPrint('✅ [Auth] User saved to Firestore: $shortCode');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shortCode', shortCode);
    await prefs.setString('uid', uid);

    return model;
  }

  /// Generates a unique 6-character short code using Crockford Base32.
  /// Retries on collision (extremely rare in practice).
  Future<String> _generateUniqueShortCode() async {
    final rng = Random.secure();
    for (int attempt = 0; attempt < 10; attempt++) {
      final code = List.generate(AppConstants.shortCodeLength, (_) {
        return AppConstants
            .shortCodeAlphabet[rng.nextInt(AppConstants.shortCodeAlphabet.length)];
      }).join();
      debugPrint('🎲 [Auth] Trying code: $code (attempt ${attempt + 1})');

      final existing = await _db
          .collection(AppConstants.usersCollection)
          .where('shortCode', isEqualTo: code)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        debugPrint('✅ [Auth] Code $code is unique!');
        return code;
      }
      debugPrint('⚠️ [Auth] Code $code already taken — retrying...');
    }
    throw Exception('Failed to generate unique short code after 10 attempts');
  }

  /// Looks up a user by their short code. Returns null if not found.
  Future<UserModel?> lookupByShortCode(String code) async {
    final normalised = code.trim().toUpperCase();
    debugPrint('🔍 [Auth] Looking up short code: $normalised');
    final result = await _db
        .collection(AppConstants.usersCollection)
        .where('shortCode', isEqualTo: normalised)
        .limit(1)
        .get();
    if (result.docs.isEmpty) {
      debugPrint('❌ [Auth] No user found for code: $normalised');
      return null;
    }
    debugPrint('✅ [Auth] Found user for code: $normalised');
    return UserModel.fromMap(result.docs.first.data());
  }

  Future<void> _updateFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .update({'fcmToken': token});
      }
    } catch (_) {}
  }

  Future<void> refreshFcmToken() async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await _updateFcmToken(uid);
  }
}
