import 'package:csc322_starter_app/models/module.dart';

class Grade {
  final String id;
  final String title;
  final List<Module> modules;

  Grade({required this.id, required this.title, required this.modules});
}