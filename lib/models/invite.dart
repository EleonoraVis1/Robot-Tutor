enum InviteStatus { PENDING, ACCEPTED, DECLINED }

class Invite {
  final String id;
  final String studentId;
  final String supervisorUid;
  final String supervisorFullName;
  final String supervisorEmail;
  final InviteStatus status;
  final String? photoUrl; 

  const Invite({
    required this.id,
    required this.studentId,
    required this.supervisorUid,
    required this.supervisorFullName,
    required this.supervisorEmail,
    required this.status,
    this.photoUrl,
  });

  String get initials {
    final parts = supervisorFullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return supervisorFullName.isNotEmpty
        ? supervisorFullName[0].toUpperCase()
        : '';
  }

  static InviteStatus statusFromString(String inviteStatusStr) {
    switch (inviteStatusStr.toLowerCase()) {
      case 'pending':
        return InviteStatus.PENDING;
      case 'accepted':
        return InviteStatus.ACCEPTED;
      case 'declined':
        return InviteStatus.DECLINED;
      default:
        return InviteStatus.DECLINED;
    }
  }
}