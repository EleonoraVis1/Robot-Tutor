import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final robotPersonaServiceProvider = Provider((ref) {
  return RobotPersonaService();
});

class RobotPersonaService {
  final _db = FirebaseFirestore.instance;

  Future<void> setPersona(String persona) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await _db
        .collection('user_profiles')
        .doc(user.uid)
        .update({'robot_persona': persona});
  }
}