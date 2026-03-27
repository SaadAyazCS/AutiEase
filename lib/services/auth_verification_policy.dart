bool requiresEmailVerification({
  required bool isGoogleUser,
  required bool isEmailVerified,
}) {
  // Strict policy for password users only.
  return !isGoogleUser && !isEmailVerified;
}
