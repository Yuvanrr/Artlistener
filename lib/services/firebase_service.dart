import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Collection references
  final CollectionReference _exhibitsCollection = FirebaseFirestore.instance.collection('exhibits');

  // Authentication methods
  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      print('Error signing in: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Firestore methods
  Stream<QuerySnapshot> getExhibits() {
    return _exhibitsCollection.snapshots();
  }

  Future<DocumentSnapshot> getExhibit(String id) async {
    return await _exhibitsCollection.doc(id).get();
  }

  Future<void> addExhibit(Map<String, dynamic> exhibit) async {
    try {
      print('Attempting to save exhibit to Firestore:');
      print('Collection: exhibits');
      print('Data: $exhibit');
      
      final docRef = await _exhibitsCollection.add(exhibit);
      print('Document added with ID: ${docRef.id}');
      
      // Verify the document was created
      final doc = await docRef.get();
      print('Document verified: ${doc.exists}');
      print('Document data: ${doc.data()}');
      
    } catch (e) {
      print('Error adding exhibit: $e');
      print('Error details: ${e.toString()}');
      rethrow;
    }
  }

  Future<void> updateExhibit(String id, Map<String, dynamic> data) async {
    try {
      await _exhibitsCollection.doc(id).update(data);
    } catch (e) {
      print('Error updating exhibit: $e');
      rethrow;
    }
  }

  Future<void> deleteExhibit(String id) async {
    try {
      await _exhibitsCollection.doc(id).delete();
    } catch (e) {
      print('Error deleting exhibit: $e');
      rethrow;
    }
  }
}
