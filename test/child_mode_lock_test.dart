import 'package:autiease/navigation/child_mode_lock_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChildModeLockController logic tests', () {
    setUp(() {
      // Reset state for each test
      ChildModeLockController.isLockedNotifier.value = false;
    });

    test('Default locked state is false', () {
      expect(ChildModeLockController.isLocked, isFalse);
    });

    test('Setting lock state notifies listeners', () {
      bool notified = false;
      ChildModeLockController.isLockedNotifier.addListener(() {
        notified = true;
      });

      ChildModeLockController.isLockedNotifier.value = true;
      expect(ChildModeLockController.isLocked, isTrue);
      expect(notified, isTrue);
    });

    test('verifyPin and hasPin validation works', () async {
      // By default, no PIN is set in memory at starting
      expect(ChildModeLockController.hasPin(), isFalse);

      // Verify that incorrect inputs return false
      expect(ChildModeLockController.verifyPin('1234'), isFalse);
    });
  });
}
