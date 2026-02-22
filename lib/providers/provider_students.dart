import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/models/student.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final studentsProvider = StreamProvider<List<Student>>((ref) {
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

      final studentsRef = firestore
          .collection('user_profiles')
          .doc(user.uid)
          .collection('students');

      return studentsRef.snapshots().asyncMap((snapshot) async {
        List<Student> students = [];

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final studentId = doc.id;
          final studentFullName = data['fullName'] as String;
          final studentEmail = data['email'] as String;

          String? photoUrl;
          try {
            photoUrl = await storage
                .ref('users/$studentId/profile_picture/userProfilePicture.jpg')
                .getDownloadURL();
          } catch (_) {
            photoUrl = null;
          }

          students.add(
            Student(
              id: studentId,
              fullName: studentFullName,
              email: studentEmail,
              photoUrl: photoUrl,
            ),
          );
        }

        return students;
    });
    },
  );
});