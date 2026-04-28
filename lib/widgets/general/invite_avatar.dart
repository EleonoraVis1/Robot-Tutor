import 'package:csc322_starter_app/models/invite.dart';
import 'package:flutter/material.dart';

class InviteAvatar extends StatelessWidget {
  final Invite invite;
  final double radius;

  const InviteAvatar({
    super.key,
    required this.invite,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    if (invite.photoUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(invite.photoUrl!),
      );
    }

    return CircleAvatar(
      radius: radius,
      child: Text(
        invite.initials,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}