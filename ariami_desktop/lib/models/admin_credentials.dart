/// Owner sign-in credentials (e.g. from [showAdminCredentialsDialog]).
class AdminCredentials {
  const AdminCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;
}
