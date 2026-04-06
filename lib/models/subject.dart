import 'package:csc322_starter_app/models/grade.dart';
import 'package:csc322_starter_app/models/module.dart';
import 'package:flutter/material.dart';

class Subject {
  final String id;        
  final String title;      
  final IconData icon;
 // final List<Module> modules;
  final List<Grade> grades;

  Subject({
    required this.id,
    required this.title,
    required this.icon,
   // required this.modules,
    this.grades = const [],
  });
}