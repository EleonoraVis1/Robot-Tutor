import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/models/grade.dart';
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
          final id = doc.id; 

          final grade = _extractGradeFromId(id);

          return Module(
            id: id,
            title: data['title'],
            subjectId: data['subject_id'],
            grade: grade,
            grade_level: data['grade_level']
          );
        }).toList();
      });
});

int _extractGradeFromId(String id) {
  final regex = RegExp(r'grade(\d+)');
  final match = regex.firstMatch(id);
  if (match != null) {
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }
  return 0; 
}

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

      final subjects = grouped.entries.where((entry) => entry.key.toLowerCase() != 'unknown').map((entry) {
        return Subject(
          id: entry.key,
          title: _capitalize(entry.key),
          icon: _subjectIcon(entry.key),
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

final subjectsWithGradesProvider = Provider<AsyncValue<List<Subject>>>((ref) {
  final modulesAsync = ref.watch(modulesProvider);

  return modulesAsync.when(
    data: (modules) {
      final Map<String, Map<int, List<Module>>> grouped = {};

      for (final m in modules) {
        grouped.putIfAbsent(m.subjectId, () => {});
        grouped[m.subjectId]!.putIfAbsent(m.grade, () => []).add(m);
      }

      final subjects = grouped.entries.map((subjectEntry) {
        final subjectId = subjectEntry.key;
        final grades = subjectEntry.value.entries.map((gradeEntry) {
          final gradeNumber = gradeEntry.key;
          return Grade(
            id: gradeNumber.toString(),
            title: 'Grade $gradeNumber',
            modules: gradeEntry.value,
          );
        }).toList();

        return Subject(
          id: subjectId,
          title: _capitalize(subjectId),
          icon: _subjectIcon(subjectId),
          grades: grades,
        );
      }).toList();

      return AsyncValue.data(subjects);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

final modulesByGradeProvider = Provider.family<AsyncValue<List<Module>>, ({String subjectId, int gradeId})>((ref, params) {
  final modulesAsync = ref.watch(modulesProvider);

  return modulesAsync.when(
    data: (modules) {
      final filtered = modules.where((m) => m.subjectId == params.subjectId && m.grade == params.gradeId).toList();
      return AsyncValue.data(filtered);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});