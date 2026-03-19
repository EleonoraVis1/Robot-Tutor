import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final robotPersonaProvider = StreamProvider<String?>((ref) {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('user_profiles')
      .doc(user.uid)
      .snapshots()
      .map((doc) => doc.data()?['robot_persona'] as String?);
});