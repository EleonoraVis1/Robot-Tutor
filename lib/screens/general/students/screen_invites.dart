// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csc322_starter_app/main.dart';
import 'package:csc322_starter_app/models/invite.dart';
import 'package:csc322_starter_app/providers/provides_invites.dart';
import 'package:csc322_starter_app/widgets/general/invite_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

// App relative file imports
import '../../../util/message_display/snackbar.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenInvites extends ConsumerStatefulWidget {
  static const routeName = '/invites';

  @override
  ConsumerState<ScreenInvites> createState() => _ScreenInvitesState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenInvitesState extends ConsumerState<ScreenInvites> {
  // The "instance variables" managed in this state
  bool _isInit = true;

  ////////////////////////////////////////////////////////////////
  // Runs the following code once upon initialization
  ////////////////////////////////////////////////////////////////
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

  ////////////////////////////////////////////////////////////////
  // Initializes state variables and resources
  ////////////////////////////////////////////////////////////////
  Future<void> _init() async {}

  Future<void> _declineInvite(Invite invite) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(uid)
        .collection('invites')
        .doc(invite.id)
        .delete();
  }

  Future<void> _acceptInvite(Invite invite) async {
    final firestore = FirebaseFirestore.instance;
    final studentUid = FirebaseAuth.instance.currentUser!.uid;
    final supervisorUid = invite.supervisorUid;
    final userProfile = ref.watch(providerUserProfile);

    final batch = firestore.batch();

    final inviteRef = firestore
        .collection('user_profiles')
        .doc(studentUid)
        .collection('invites')
        .doc(invite.id);

    final studentSupervisorRef = firestore
        .collection('user_profiles')
        .doc(studentUid)
        .collection('supervisors')
        .doc(supervisorUid);

    final supervisorStudentRef = firestore
        .collection('user_profiles')
        .doc(supervisorUid)
        .collection('students')
        .doc(studentUid);

    batch.update(inviteRef, {
      'status': 'Accepted',
      'respondedAt': FieldValue.serverTimestamp(),
    });

    batch.set(studentSupervisorRef, {
      'uid': supervisorUid,
      'fullName': invite.supervisorFullName,
      'email': invite.supervisorEmail,
      'addedAt': FieldValue.serverTimestamp(),
    });

    batch.set(supervisorStudentRef, {
      'uid': studentUid,
      'fullName': userProfile.firstName + " " + userProfile.lastName,
      'email': userProfile.email,
      'addedAt': FieldValue.serverTimestamp(),
    });

    batch.delete(inviteRef);
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final invitesAsync = ref.watch(invitesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Invites"),
        centerTitle: true,
      ),
      body: invitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (invites) {
          if (invites.isEmpty) {
            return const Center(child: Text("No invites"));
          }

          return ListView.builder(
            itemCount: invites.length,
            itemBuilder: (context, index) {
              final invite = invites[index];

              return ListTile(
                leading: InviteAvatar(invite: invite),
                title: Text("${invite.supervisorFullName} wants to be your supervisor"),
                subtitle: Text(invite.supervisorEmail),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: "Decline",
                      onPressed: () => _declineInvite(invite),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: "Accept",
                      onPressed: () => _acceptInvite(invite),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
