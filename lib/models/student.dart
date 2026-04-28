class Student {
  final String id;
  final String fullName;
  final String email;
  final String? photoUrl; 

  const Student({
    required this.id,
    required this.fullName,
    required this.email,
    this.photoUrl,
  });

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return fullName.isNotEmpty
        ? fullName[0].toUpperCase()
        : '';
  }
}