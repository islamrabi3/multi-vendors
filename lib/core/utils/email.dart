/// One definition of what counts as an email address.
///
/// `contains('@')` was accepting `a@`, `@b`, `ahmed @gmail.com` and
/// `name@gmail` — all of which the form let through and the auth server then
/// refused with a message about validating an email address, which the app
/// could only show as a generic failure. Checking the same shape the server
/// does means the customer is told at the field, before they lose the form.
///
/// Deliberately not exhaustive: it rejects the mistakes people actually make
/// (a missing dot in the domain, a space, a missing half) and leaves the rest
/// to the confirmation email.
final _emailPattern = RegExp(
  r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+"
  r'@'
  r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
);

bool isValidEmail(String? raw) {
  final email = raw?.trim() ?? '';
  if (email.isEmpty || email.length > 254) return false;
  return _emailPattern.hasMatch(email);
}

/// What to send to the server: no stray spaces, and lower case, so the same
/// person does not end up with two accounts over a capital letter.
String normalizeEmail(String raw) => raw.trim().toLowerCase();
