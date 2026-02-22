import 'package:csc322_starter_app/models/student.dart';
import 'package:flutter/material.dart';

class StudentAvatar extends StatelessWidget {
  final Student student;
  final double radius;

  const StudentAvatar({
    super.key,
    required this.student,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    if (student.photoUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(student.photoUrl!),
      );
    }

    return CircleAvatar(
      radius: radius,
      child: Text(
        student.initials,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}