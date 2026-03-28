// -----------------------------------------------------------------------
// Filename: widget_app_drawer.dart
// Original Author: Wyatt Bodle
// Creation Date: 6/10/2024
// Copyright: (c) 2024 CSC322
// Description: This file contains the primary scaffold for the app.

//////////////////////////////////////////////////////////////////////////
// Imports
//////////////////////////////////////////////////////////////////////////
// Flutter external package imports
import 'package:csc322_starter_app/screens/settings/screen_settings.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:csc322_starter_app/widgets/navigation/widget_primary_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

// App relative file imports
import '../../widgets/general/widget_scrollable_background.dart';
import '../auth/screen_profile_setup.dart';

final profileBottomNavTabIndex = StateProvider.autoDispose<int>((ref) => 0);

//////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the
// state object.
//////////////////////////////////////////////////////////////////
class ScreenProfile extends ConsumerStatefulWidget {
  const ScreenProfile({super.key});

  static const routeName = '/profile';

  @override
  ConsumerState<ScreenProfile> createState() => _ScreenProfileState();
}

//////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////
class _ScreenProfileState extends ConsumerState<ScreenProfile> {
  //////////////////////////////////////////////////////////////////////////
  // Primary Flutter method overriden which describes the layout
  // and bindings for this widget.
  //////////////////////////////////////////////////////////////////////////

  Widget _getScreenToDisplay(int currentTabIndex) {
    if (currentTabIndex == 0)
      return ScrollableBackground(
        child: ScreenProfileSetup(
          isAuth: false,
        ),
        padding: 15
      );
    else if (currentTabIndex == 1)
      return ScreenSettings();
    else
      return ScrollableBackground(
        child: ScreenProfileSetup(
          isAuth: false,
        ),
        padding: 15
      );
  }

  Widget _getAppBarTitle(int currentTabIndex) {
    if (currentTabIndex == 0)
      return Text("Profile");
    else if (currentTabIndex == 1)
      return Text("Settings");
    else 
      return Text("");
  }

  @override
  Widget build(BuildContext context) {
    final currentTabIndex = ref.watch(profileBottomNavTabIndex);
    // Return the widget to show
    return Scaffold(
      appBar: WidgetPrimaryAppBar(
        title: _getAppBarTitle(currentTabIndex),
      ),
      body: _getScreenToDisplay(currentTabIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentTabIndex,
        onTap: (index) {
          ref.read(profileBottomNavTabIndex.notifier).state = index;
        },
        items: [
          BottomNavigationBarItem(
            label: "Profile",
            activeIcon: Icon(Icons.person_2_outlined),
            icon: Icon(Icons.person_2_outlined)
          ),
          BottomNavigationBarItem(
            label: "Settings",
            activeIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings)
          ),
        ],
      ),
    );
  }
}