// -----------------------------------------------------------------------
// Filename: screen_home.dart
// Original Author: Dan Grissom
// Creation Date: 10/31/2024
// Copyright: (c) 2024 CSC322
// Description: This file contains the home screen. After login, students
//              see a subject-selection grid; supervisors see a student
//              list (placeholder while auth/DB work is pending).

//////////////////////////////////////////////////////////////////////////
// Imports
//////////////////////////////////////////////////////////////////////////
import 'dart:async';

import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../providers/provider_user_profile.dart';
import '../../main.dart';

//////////////////////////////////////////////////////////////////////////
// DEBUG TOGGLE — remove once real auth assigns roles
// Set to UserRole.STUDENT or UserRole.SUPERVISOR to preview each view.
//////////////////////////////////////////////////////////////////////////
// const UserRole _kDebugRole = UserRole.STUDENT;
const UserRole _kDebugRole = UserRole.SUPERVISOR;

//////////////////////////////////////////////////////////////////////////
// Placeholder subject data
//////////////////////////////////////////////////////////////////////////
const List<Map<String, dynamic>> _kSubjects = [
  {'title': 'Math', 'icon': Icons.calculate},
  {'title': 'Korean', 'icon': Icons.language},
  {'title': 'Physics', 'icon': Icons.science},
  {'title': 'English', 'icon': Icons.menu_book},
];

//////////////////////////////////////////////////////////////////////////
// Placeholder student data — add entries here to test the list view
// e.g. {'name': 'Jane Doe', 'email': 'jane@example.com'}
//////////////////////////////////////////////////////////////////////////
const List<Map<String, String>> _kPlaceholderStudents = [];

//////////////////////////////////////////////////////////////////////////
// ScreenHome
//////////////////////////////////////////////////////////////////////////
class ScreenHome extends ConsumerStatefulWidget {
  static const routeName = '/home';

  const ScreenHome({super.key});

  @override
  ConsumerState<ScreenHome> createState() => _ScreenHomeState();
}

class _ScreenHomeState extends ConsumerState<ScreenHome> {
  bool _isInit = true;

  @override
  void didChangeDependencies() {
    if (_isInit) {
      _init();
      _isInit = false;
      super.didChangeDependencies();
    }
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> _init() async {}

  UserRole _resolveRole(ProviderUserProfile profileProvider) {
    // TODO: remove _kDebugRole fallback once real auth sets userRole
    // if (!profileProvider.dataLoaded) return _kDebugRole;
    // return profileProvider.userRole;
    return _kDebugRole;
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = ref.watch(providerUserProfile);
    final UserRole role = _resolveRole(profileProvider);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: WidgetPrimaryAppBar(
        title: Text(
          role == UserRole.SUPERVISOR ? 'Supervisor Dashboard' : 'Welcome',
        ),
      ),
      body: role == UserRole.SUPERVISOR
          ? _buildSupervisorView(profileProvider)
          : _buildStudentView(profileProvider),
    );
  }

  ////////////////////////////////////////////////////////////////
  // STUDENT VIEW — subject selection grid
  ////////////////////////////////////////////////////////////////
  Widget _buildStudentView(ProviderUserProfile profileProvider) {
    final String firstName = profileProvider.dataLoaded
        ? profileProvider.firstName
        : 'there';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Hello, $firstName! 👋\nWhat would you like to learn today?',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          const Text(
            'Subjects',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: _kSubjects
                  .map(
                    (s) => _SubjectCard(
                      title: s['title'] as String,
                      icon: s['icon'] as IconData,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  ////////////////////////////////////////////////////////////////
  // SUPERVISOR VIEW — student list
  ////////////////////////////////////////////////////////////////
  Widget _buildSupervisorView(ProviderUserProfile profileProvider) {
    final String firstName = profileProvider.dataLoaded
        ? profileProvider.firstName
        : 'Supervisor';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Hello, $firstName! 👋',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Here are your students:',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _kPlaceholderStudents.isEmpty
                ? _buildEmptyStudentState()
                : _buildStudentList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStudentState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_outlined, size: 72, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No students yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Students will appear here once assigned.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    return ListView.separated(
      itemCount: _kPlaceholderStudents.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final student = _kPlaceholderStudents[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blueGrey[100],
            child: Text(
              student['name']![0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(student['name'] ?? ''),
          subtitle: Text(student['email'] ?? ''),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // TODO: navigate to student detail screen
          },
        );
      },
    );
  }
}

//////////////////////////////////////////////////////////////////////////
// Subject card widget
//////////////////////////////////////////////////////////////////////////
class _SubjectCard extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SubjectCard({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // TODO: navigate to subject screen
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.blueGrey[700]),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
