// Flutter imports
import 'dart:async';

// Flutter external package imports
import 'package:csc322_starter_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

//////////////////////////////////////////////////////////////////////////
// StateFUL widget which manages state. Simply initializes the state object.
//////////////////////////////////////////////////////////////////////////
class ScreenAddStudentSupervisor extends ConsumerStatefulWidget {
  static const routeName = '/add_student';

  @override
  ConsumerState<ScreenAddStudentSupervisor> createState() => _ScreenAddStudentSupervisorState();
}

//////////////////////////////////////////////////////////////////////////
// The actual STATE which is managed by the above widget.
//////////////////////////////////////////////////////////////////////////
class _ScreenAddStudentSupervisorState extends ConsumerState<ScreenAddStudentSupervisor> {
  // The "instance variables" managed in this state
  bool _isInit = true;
  final _formKey = GlobalKey<FormState>();
  var _userEmail = "";
  var _knownAs = "";
  

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

  Future<void> _sendRequest(String fullName, String superEmail) async {
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();

    final supervisorUid = FirebaseAuth.instance.currentUser!.uid;
    final supervisorFullName = fullName;
    final supervisorEmail = superEmail;

    final firestore = FirebaseFirestore.instance;
    final query = await firestore
        .collection('user_profiles')
        .where('email_lowercase', isEqualTo: _userEmail.toLowerCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No user found with that email."))); 
      return;
    }

    final studentDoc = query.docs.first;
    final studentUid = studentDoc.id;

    await firestore
        .collection('user_profiles')
        .doc(studentUid)
        .collection('invites')
        .add({
      'supervisorUid': supervisorUid,
      'supervisorFullName': supervisorFullName,
      'email': supervisorEmail,
      'knownAs': _knownAs,
      'status': 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invite sent successfully.")));
    Navigator.of(context).pop();
  }

  Future<void> _cancelAdd() async {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(providerUserProfile);
    final supervisorFullName = userProfile.firstName + " " + userProfile.lastName;
    final supervisorEmail = userProfile.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Register New Student"),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Student Email",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          maxLength: 254,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.isEmpty ||
                                value.trim().length < 3 ||
                                value.trim().length > 254) {
                              return 'Must be between 3 and 254 characters';
                            } else if (!(value.contains("@"))) {
                              return 'Must contain \'@\' character';
                            }
                            return null;
                          },
                          onSaved: (value) => _userEmail = value!,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          maxLength: 254,
                          decoration: const InputDecoration(
                            labelText: 'Know as? (Mother, Father, Teacher)'
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.isEmpty ||
                                value.trim().length < 3 ||
                                value.trim().length > 254) {
                              return 'Must be between 3 and 254 characters';
                            }
                            return null;
                          },
                          onSaved: (value) => _knownAs = value!,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton.icon(
                                onPressed: _cancelAdd, 
                                label: const Text("Cancel"),
                                icon: const Icon(Icons.cancel),
                                style: ElevatedButton.styleFrom(
                                  fixedSize: Size(130, 15),
                                  textStyle: TextStyle(fontSize: 18),
                                  iconSize: 18,
                                ),
                              ),
                            ),
                            Spacer(),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _sendRequest(supervisorFullName, supervisorEmail);
                                },
                                icon: const Icon(Icons.send),
                                label: const Text("Send Request"),
                                style: ElevatedButton.styleFrom(
                                  fixedSize: Size(180, 15),
                                  textStyle: TextStyle(fontSize: 18),
                                  iconSize: 18,
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
