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
import 'package:csc322_starter_app/models/invite.dart';
import 'package:csc322_starter_app/models/user_profile.dart';
import 'package:csc322_starter_app/providers/provider_firestore.dart';
import 'package:csc322_starter_app/providers/provider_students.dart';
import 'package:csc322_starter_app/providers/provides_invites.dart';
import 'package:csc322_starter_app/screens/auth/screen_login_validation.dart';
import 'package:csc322_starter_app/screens/general/students/screen_baymin_student.dart';
import 'package:csc322_starter_app/screens/general/students/screen_home_student.dart';
import 'package:csc322_starter_app/screens/general/students/screen_invites.dart';
import 'package:csc322_starter_app/screens/general/students/screen_quizzes_student.dart';
import 'package:csc322_starter_app/screens/general/students/screen_student_supervisors.dart';
import 'package:csc322_starter_app/screens/general/supervisors/screen_notifications_supervisor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

// App relative file imports
import '../../widgets/navigation/widget_primary_scaffold.dart';
import '../../screens/settings/screen_profile.dart';
import '../../providers/provider_user_profile.dart';
import '../../screens/settings/screen_settings.dart';
import '../general/widget_profile_avatar.dart';
import '../../providers/provider_auth.dart';
import '../../main.dart';

enum BottomNavSelection { HOME_SCREEN, PROFILE_SCREEN, SETTINGS_SCREEN }

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
          final invitesAsync = ref.watch(invitesProvider);
          final notificationsAsync = ref.watch(notificationsProvider);

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
                onTap: () => isSupervisor ? Navigator.of(context).pop() : context.push(ScreenHomeStudent.routeName)
              ),
              ListTile(
                leading: Icon(Icons.person),
                title: Text('Profile'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(ScreenProfile.routeName);
                },
              ),
              if (isSupervisor)
                ListTile(
                  leading: const Icon(Icons.notifications),
                  title: const Text('Notifications'),
                  trailing: notificationsAsync.when(
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                    data: (notifications) {
                      final unreadCount =
                          notifications.where((n) => n['read'] == false).length;

                      if (unreadCount == 0) return const SizedBox();

                      return Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(ScreenNotifications.routeName);
                  },
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
                  leading: Icon(Icons.person), 
                  title: Text('Supervisors'), 
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(ScreenStudentSupervisors.routeName);
                  }
                ),
              if (!isSupervisor)
                ListTile(
                leading: const Icon(Icons.forward_to_inbox),
                title: const Text('Invites'),
                trailing: invitesAsync.when(
                  loading: () => const SizedBox(), 
                  error: (_, __) => const SizedBox(),
                  data: (invites) {
                    final pendingCount = invites
                      .where((i) => i.status == InviteStatus.PENDING)
                      .length;

                    if (pendingCount == 0) return const SizedBox();

                    final text = '$pendingCount';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12), 
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(ScreenInvites.routeName);
                },
              ),
              Divider(),
              // ListTile(
              //   leading: Icon(Icons.settings),
              //   title: Text('Settings'),
              //   onTap: () {
              //     // Close the drawer
              //     Navigator.of(context).pop();
              //     context.push(ScreenSettings.routeName, extra: false);
              //   },
              // ),
              ListTile(
                leading: Icon(Icons.exit_to_app),
                title: Text('Logout'),
                onTap: () async {
                  _providerAuth.clearAuthedUserDetailsAndSignout();
                  context.push(ScreenLoginValidation.routeName);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
