import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final moduleResultProvider = StreamProvider.family<
    DocumentSnapshot<Map<String, dynamic>>?, ({
  String studentUid,
  String moduleId,
})>((ref, params) {
  return FirebaseFirestore.instance
      .collection('user_profiles')
      .doc(params.studentUid)
      .collection('module_results')
      .doc(params.moduleId)
      .snapshots()
      .map((doc) => doc.exists ? doc : null);
});