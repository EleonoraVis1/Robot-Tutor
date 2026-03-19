import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> setActiveUser(String uid) async {
    await _db.collection('reachy-mini').doc('reachy1').update({
      'active_user': uid,
    });
  }

  Future<void> clearActiveUser() async {
    await _db.collection('reachy-mini').doc('reachy1').update({
      'active_user': null,
    });
  }
}