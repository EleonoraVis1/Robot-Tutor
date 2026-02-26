// -----------------------------------------------------------------------
// Filename: widget_app_drawer.dart
// Original Author: Dan Grissom
// Creation Date: 5/27/2024
// Copyright: (c) 2024 CSC322
// Description: This file contains the primary scaffold for the app.

//////////////////////////////////////////////////////////////////////////
// Imports
//////////////////////////////////////////////////////////////////////////
// Flutter external package imports
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/screens/general/students/screen_baymin_student.dart';
import 'package:csc322_starter_app/screens/general/students/screen_invites.dart';
import 'package:csc322_starter_app/screens/general/students/screen_quizzes_student.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_quizzes_supervisor.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_subject_supervisor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

// App relative file imports
import '../../widgets/navigation/widget_primary_scaffold.dart';
import '../../screens/settings/screen_profile_edit.dart';
import '../../providers/provider_user_profile.dart';
import '../../screens/settings/screen_settings.dart';
import '../general/widget_profile_avatar.dart';
import '../../providers/provider_auth.dart';
import '../../main.dart';

enum BottomNavSelection { HOME_SCREEN, ALTERNATE_SCREEN }

//////////////////////////////////////////////////////////////////
// StateLESS widget which only has data that is initialized when
// widget is created (cannot update except when re-created).
//////////////////////////////////////////////////////////////////
class WidgetAppDrawer extends StatelessWidget {
  ////////////////////////////////////////////////////////////////
  // Primary Flutter method overriden which describes the layout
  // and bindings for this widget.
  ////////////////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final ProviderAuth _providerAuth = ref.watch(providerAuth);
          final ProviderUserProfile _providerUserProfile = ref.watch(providerUserProfile);
          final userProfile = ref.watch(providerUserProfile);
          final isSupervisor = userProfile.userType == UserType.SUPERVISOR;

          return Column(
            children: <Widget>[
              AppBar(
                title: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    ProfileAvatar(
                      radius: 15,
                      userImage: _providerUserProfile.userImage,
                      userWholeName: _providerUserProfile.wholeName,
                    ),
                    const SizedBox(width: 10),
                    Text('Welcome ${_providerUserProfile.firstName}'),
                  ],
                ),
                // ,
                automaticallyImplyLeading: false,
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.home), 
                title: Text('Home'), 
                onTap: () => Navigator.of(context).pop()
              ),
              ListTile(
                leading: Icon(Icons.person),
                title: Text('Profile'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(ScreenProfileEdit.routeName);
                },
              ),
              if (!isSupervisor)
                ListTile(
                  leading: Icon(Icons.book_online_outlined), 
                  title: Text('Quizzes'), 
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(ScreenQuizzesStudent.routeName);
                  }
                ),
              if (!isSupervisor)
                ListTile(
                  leading: Icon(Icons.bolt_outlined), 
                  title: Text('BAY-min Persona'), 
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(ScreenBayminStudent.routeName);
                  }
                ),
              if (!isSupervisor)
                Divider(),
              if (!isSupervisor)
                ListTile(
                  leading: Icon(Icons.forward_to_inbox), 
                  title: Text('Invites'), 
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(ScreenInvites.routeName);
                  }
                ),
              Divider(),
              ListTile(
                leading: Icon(Icons.settings),
                title: Text('Settings'),
                onTap: () {
                  // Close the drawer
                  Navigator.of(context).pop();
                  context.push(ScreenSettings.routeName, extra: false);
                },
              ),
              ListTile(
                leading: Icon(Icons.exit_to_app),
                title: Text('Logout'),
                onTap: () {
                  _providerAuth.clearAuthedUserDetailsAndSignout();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
