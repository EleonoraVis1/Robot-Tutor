// -----------------------------------------------------------------------
// Filename: main.dart
// Original Author: Dan Grissom
// Creation Date: 5/18/2024
// Copyright: (c) 2024 CSC322
// Description: This file is the main entry point for the app and
//              initializes the app and the router.

//////////////////////////////////////////////////////////////////////////
// Imports
//////////////////////////////////////////////////////////////////////////
// Dart imports

// Flutter external package imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/providers/provider_current_module.dart';
import 'package:csc322_starter_app/screens/auth/screen_auth.dart';
import 'package:csc322_starter_app/screens/auth/screen_profile_setup.dart';
import 'package:csc322_starter_app/screens/auth/screen_role.dart';
import 'package:csc322_starter_app/screens/general/students/screen_baymin_student.dart';
import 'package:csc322_starter_app/screens/general/students/screen_chathistory_student.dart';
import 'package:csc322_starter_app/screens/general/students/screen_invites.dart';
import 'package:csc322_starter_app/screens/general/students/screen_module.dart';
import 'package:csc322_starter_app/screens/general/students/screen_quizzes_student.dart';
import 'package:csc322_starter_app/screens/general/students/screen_subject.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_addstudent_supervisor.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_chathistory_supervisor.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_home_supervisor.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_studentinfo_supervisor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

// App relative file imports
import 'screens/general/students/screen_home_student.dart';
import 'widgets/navigation/widget_primary_scaffold.dart';
import 'screens/auth/screen_login_validation.dart';
import 'screens/settings/screen_profile_edit.dart';
import 'providers/provider_user_profile.dart';
import 'screens/settings/screen_settings.dart';
import 'providers/provider_auth.dart';
import 'util/file/util_file.dart';
import 'firebase_options.dart';
import 'theme/theme.dart';

//////////////////////////////////////////////////////////////////////////
// Providers
//////////////////////////////////////////////////////////////////////////
// Create a ProviderContainer to hold the providers
final ProviderContainer providerContainer = ProviderContainer();

// Create providers
final providerUserProfile = ChangeNotifierProvider<ProviderUserProfile>(
  (ref) => ProviderUserProfile(),
);
final providerAuth = ChangeNotifierProvider<ProviderAuth>(
  (ref) => ProviderAuth(),
);

//////////////////////////////////////////////////////////////////////////
// MAIN entry point to start app.
//////////////////////////////////////////////////////////////////////////
Future<void> main() async {
  // Initialize widgets and firebase
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with the default options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize the app directory
  await UtilFile.init();

  // Get references to providers that will be needed in other providers
  final ProviderUserProfile userProfileProvider = providerContainer.read(
    providerUserProfile,
  );
  final ProviderAuth authProvider = providerContainer.read(providerAuth);

  // Initialize providers
  await userProfileProvider.initProviders(authProvider);
  authProvider.initProviders(userProfileProvider);

  // Run the app
  runApp(
    UncontrolledProviderScope(
      container: providerContainer,
      child:  MyApp(),
    ),
  );
}

//////////////////////////////////////////////////////////////////////////
// Main class which is the root of the app.
//////////////////////////////////////////////////////////////////////////
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _MyAppState extends State<MyApp> {
  // The "instance variables" managed in this state
  // NONE

  // Router

  final GoRouter _router = GoRouter(
    initialLocation: ScreenLoginValidation.routeName,
    routes: [
      GoRoute(
        path: ScreenLoginValidation.routeName,
        builder: (context, state) => const ScreenLoginValidation(),
      ),
      GoRoute(
        path: ScreenSettings.routeName,
        builder: (context, state) => ScreenSettings(),
      ),
      GoRoute(
        path: ScreenProfileEdit.routeName,
        builder: (context, state) => const ScreenProfileEdit(),
      ),
      GoRoute(
        path: WidgetPrimaryScaffold.routeName,
        builder: (BuildContext context, GoRouterState state) =>
          const WidgetPrimaryScaffold(),
      ),

      // Student home flow
      GoRoute(
        path: ScreenHomeStudent.routeName,
        builder: (context, state) => ScreenHomeStudent(supervisorView: false, studentUid: null),
      ),
      GoRoute(
        path: '/subject/:subjectId',
        builder: (context, state) {
          final subjectId = state.pathParameters['subjectId']!;
          return ScreenSubject(subjectId: subjectId, studentUid: null,);
        },
        routes: [
          GoRoute(
            path: 'module/:moduleId',
            builder: (context, state) {
              final subjectId = state.pathParameters['subjectId']!;
              final moduleId = state.pathParameters['moduleId']!;
              return ScreenModule(
                subjectId: subjectId,
                moduleId: moduleId,
                studentUid: null, // student will use their own UID
              );
            },
            routes: [
              GoRoute(
                path: 'quiz',
                builder: (context, state) {
                  final subjectId = state.pathParameters['subjectId']!;
                  final moduleId = state.pathParameters['moduleId']!;
                  return ScreenQuiz(
                    subjectId: subjectId,
                    moduleId: moduleId,
                    studentUid: null, // student uses their own UID
                  );
                },
              ),
              GoRoute(
                path: 'chat',
                builder: (context, state) {
                  final moduleId = state.pathParameters['moduleId']!;
                  return ScreenChathistoryStudent(moduleId: moduleId);
                },
              ),
            ],
          ),
        ],
      ),
      // Supervisor home
      GoRoute(
        path: ScreenHomeSupervisor.routeName,
        builder: (context, state) => ScreenHomeSupervisor(),
        routes: [
          // Supervisor selects a student -> show student's subjects
          GoRoute(
            path: 'student/:studentUid',
            builder: (context, state) {
              final studentUid = state.pathParameters['studentUid']!;
              return ScreenHomeStudent(
                supervisorView: true,
                studentUid: studentUid,
              );
            },
            routes: [
              // Subject
              GoRoute(
                path: 'subject/:subjectId',
                builder: (context, state) {
                  final studentUid = state.pathParameters['studentUid']!;
                  final subjectId = state.pathParameters['subjectId']!;

                  return ScreenSubject(
                    subjectId: subjectId,
                    studentUid: studentUid,
                  );
                },
                routes: [
                  // Module
                  GoRoute(
                    path: 'module/:moduleId',
                    builder: (context, state) {
                      final studentUid = state.pathParameters['studentUid']!;
                      final subjectId = state.pathParameters['subjectId']!;
                      final moduleId = state.pathParameters['moduleId']!;

                      return ScreenModule(
                        studentUid: studentUid,
                        subjectId: subjectId,
                        moduleId: moduleId,
                      );
                    },
                    routes: [
                      GoRoute(
                        path: 'chat',
                        builder: (context, state) {
                          final studentUid = state.pathParameters['studentUid']!;
                          final moduleId = state.pathParameters['moduleId']!;

                          return ScreenChathistorySupervisor(
                            studentUid: studentUid,
                            moduleId: moduleId,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute( path: ScreenInvites.routeName, builder: (context, state) => ScreenInvites(), ),
      GoRoute( path: ScreenBayminStudent.routeName, builder: (context, state) => ScreenBayminStudent(), ),
      GoRoute( path: ScreenAddStudentSupervisor.routeName, builder: (context, state) => ScreenAddStudentSupervisor(), ),
    ],
  );

  //////////////////////////////////////////////////////////////////////////
  // Primary Flutter method overriden which describes the layout
  // and bindings for this widget.
  //////////////////////////////////////////////////////////////////////////

  // ToDO: start something
  // This widget is the root of your application.

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'BAY-min tutor',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
    );
  }
}
