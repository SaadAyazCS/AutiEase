import 'package:autiease/services/auth_verification_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('requiresEmailVerification', () {
    test('requires verification for unverified password users', () {
      final blocked = requiresEmailVerification(
        isGoogleUser: false,
        isEmailVerified: false,
      );

      expect(blocked, isTrue);
    });

    test('does not require verification for verified password users', () {
      final blocked = requiresEmailVerification(
        isGoogleUser: false,
        isEmailVerified: true,
      );

      expect(blocked, isFalse);
    });

    test('does not require verification for Google users', () {
      final blocked = requiresEmailVerification(
        isGoogleUser: true,
        isEmailVerified: false,
      );

      expect(blocked, isFalse);
    });
  });
}
