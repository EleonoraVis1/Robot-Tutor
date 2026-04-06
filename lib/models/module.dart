import 'package:csc322_starter_app/models/grade.dart';

class Module {
  final String id;
  final String title;
  final String subjectId;
  final int grade;

  Module({
    required this.id,
    required this.title,
    required this.subjectId,
    required this.grade
  });
}