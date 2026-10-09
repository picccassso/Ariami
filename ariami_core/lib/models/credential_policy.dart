/// Account credential length rules shared by the server and every client UI.
/// Pure Dart so web builds can import it.
class CredentialPolicy {
  const CredentialPolicy._();

  static const int minUsernameLength = 3;

  /// Existing shorter passwords keep working for login; only registration and
  /// password changes enforce this.
  static const int minPasswordLength = 10;
}
