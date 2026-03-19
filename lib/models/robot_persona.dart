import 'package:flutter/material.dart';

class RobotPersona {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  const RobotPersona({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color
  });
}

const robotPersonas = [
  RobotPersona(
    id: "friendly",
    name: "Friendly Helper",
    description: "Encouraging and supportive",
    icon: Icons.favorite,
    color: Colors.pink,
  ),
  RobotPersona(
    id: "teacher",
    name: "Strict Teacher",
    description: "Focused on learning",
    icon: Icons.school,
    color: Colors.blue,
  ),
  RobotPersona(
    id: "motivator",
    name: "Motivational Coach",
    description: "Pushes you forward",
    icon: Icons.fitness_center,
    color: Colors.orange,
  ),
  RobotPersona(
    id: "funny",
    name: "Funny Companion",
    description: "Adds humor to learning",
    icon: Icons.sentiment_satisfied,
    color: Colors.green,
  ),
];