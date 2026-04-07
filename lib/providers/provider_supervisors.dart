import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

final studentSupervisorsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, studentId) {
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance;

  return firestore
      .collection('user_profiles')
      .doc(studentId)
      .collection('supervisors')
      .snapshots()
      .asyncMap((snapshot) async {
    if (snapshot.docs.isEmpty) return [];

    final futures = snapshot.docs.map((doc) async {
      final data = doc.data();

      final supervisorId = doc.id;

      String? photoUrl;
      try {
        photoUrl = await storage
            .ref()
            .child('users/$supervisorId/profile_picture/userProfilePicture.jpg')
            .getDownloadURL()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        photoUrl = null;
      }

      return {
        'id': supervisorId,
        'fullName': data['fullName'] ?? 'No Name', 
        'email': data['email'] ?? 'No Email',      
        'photoUrl': photoUrl,
      };
    });

    final results = await Future.wait(futures);
    return results.whereType<Map<String, dynamic>>().toList();
  });
});