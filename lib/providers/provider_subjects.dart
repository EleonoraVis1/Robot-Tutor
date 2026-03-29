import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/models/module.dart';
import 'package:csc322_starter_app/models/subject.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final modulesProvider = StreamProvider<List<Module>>((ref) {
  return FirebaseFirestore.instance
      .collection('modules')
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          return Module(
            id: doc.id,
            title: data['title'],
            subjectId: data['subject_id'], 
          );
        }).toList();
      });
});

final studentModulesProvider = StreamProvider.family<
    Map<String, dynamic>, String>((ref, studentId) {
  return FirebaseFirestore.instance
      .collection('user_profiles')
      .doc(studentId)
      .collection('modules')
      .snapshots()
      .map((snapshot) {
        final Map<String, dynamic> modulesMap = {};

        for (var doc in snapshot.docs) {
          modulesMap[doc.id] = doc.data();
        }

        return modulesMap;
      });
});

final exampleQuestionNumProvider = StreamProvider.family<
    int,
    ({String studentId, String moduleId})>((ref, params) {

  final moduleRef = FirebaseFirestore.instance
      .collection('user_profiles')
      .doc(params.studentId)
      .collection('modules')
      .doc(params.moduleId);

  return moduleRef.snapshots().map((doc) {
    if (!doc.exists) return 0;

    final data = doc.data();
    return (data?['example_question_num'] as int?) ?? -1;
  });
});

final subjectsProvider = Provider<AsyncValue<List<Subject>>>((ref) {
  final modulesAsync = ref.watch(modulesProvider);

  return modulesAsync.when(
    data: (modules) {
      final Map<String, List<Module>> grouped = {};

      for (final m in modules) {
        grouped.putIfAbsent(m.subjectId, () => []).add(m);
      }

      final subjects = grouped.entries.map((entry) {
        return Subject(
          id: entry.key,
          title: _capitalize(entry.key),
          icon: _subjectIcon(entry.key),
          modules: entry.value,
        );
      }).toList();

      return AsyncValue.data(subjects);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

IconData _subjectIcon(String key) {
  switch (key.toLowerCase()) {
    case 'math': return Icons.calculate;
    case 'english': return Icons.menu_book;
    case 'science': return Icons.science;
    default: return Icons.school;
  }
}