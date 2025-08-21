import 'package:flutter/material.dart';
import '../services/firebase_service.dart';

class FirebaseProvider extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = false;
  String? _error;

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _firebaseService.currentUser != null;

  // Sign in with email and password
  Future<bool> signIn(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _firebaseService.signInWithEmailAndPassword(email, password);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _firebaseService.signOut();
    notifyListeners();
  }

  // Get all exhibits
  Stream<dynamic> getExhibits() {
    return _firebaseService.getExhibits();
  }

  // Get a single exhibit
  Future<dynamic> getExhibit(String id) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final doc = await _firebaseService.getExhibit(id);
      return doc;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a new exhibit
  Future<bool> addExhibit(Map<String, dynamic> exhibit) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _firebaseService.addExhibit(exhibit);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update an existing exhibit
  Future<bool> updateExhibit(String id, Map<String, dynamic> data) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _firebaseService.updateExhibit(id, data);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete an exhibit
  Future<bool> deleteExhibit(String id) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _firebaseService.deleteExhibit(id);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
