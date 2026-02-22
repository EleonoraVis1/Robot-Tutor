import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/models/invite.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final invitesProvider = StreamProvider<List<Invite>>((ref) {
  final authAsync = ref.watch(authStateProvider);

  return authAsync.when(
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
    data: (user) {
      if (user == null) {
        return const Stream.empty();
      }

  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance;

  final invitesRef = firestore
      .collection('user_profiles')
      .doc(user.uid)
      .collection('invites');

  return invitesRef.snapshots().asyncMap((snapshot) async {
    List<Invite> invites = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final inviteId = doc.id;
      final supervisorUid = data['supervisorUid'] as String;
      final supervisorFullName = data['supervisorFullName'] as String;
      final statusStr = data['status'] as String;
      final supervisorEmail = data['email'] as String;

      String? photoUrl;
      try {
        photoUrl = await storage
            .ref('users/$supervisorUid/profile_picture/userProfilePicture.jpg')
            .getDownloadURL();
      } catch (_) {
        photoUrl = null;
      }

      invites.add(
        Invite(
          id: inviteId,
          studentId: user.uid,
          supervisorUid: supervisorUid,
          supervisorFullName: supervisorFullName,
          supervisorEmail: supervisorEmail,
          status: Invite.statusFromString(statusStr),
          photoUrl: photoUrl,
        ),
      );
    }

    return invites;
      });
    },
  );
});