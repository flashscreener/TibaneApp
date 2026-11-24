import 'package:flutter_test/flutter_test.dart';
import 'package:tibaneapp/services/wallet/creation.dart';

/// Phase 2 (Atonline-parity) — pure creation-committee decisions (§5.2 / D5).
/// The biometric enrollment prompt, keygen, and at-rest writes are
/// device-verified.
void main() {
  group('creationModeFor', () {
    test('biometric device → biometric committee', () {
      expect(creationModeFor(hasBiometric: true), CreationMode.biometric);
    });

    test('no biometric retains an independent device key', () {
      expect(creationModeFor(hasBiometric: false), CreationMode.deviceStorage);
    });

    test('debug storage override never duplicates the password share', () {
      expect(
        creationModeFor(hasBiometric: true, forceUnsafe: true),
        CreationMode.deviceStorage,
      );
    });
  });

  group('creationKeyTypes', () {
    test('biometric → [StoreKey, RemoteKey, Password]', () {
      expect(creationKeyTypes(CreationMode.biometric), [
        'StoreKey',
        'RemoteKey',
        'Password',
      ]);
    });

    test('device storage preserves [StoreKey, RemoteKey, Password]', () {
      expect(creationKeyTypes(CreationMode.deviceStorage), [
        'StoreKey',
        'RemoteKey',
        'Password',
      ]);
    });

    test('both committees have ≥3 keys (multiCreate floor)', () {
      for (final mode in CreationMode.values) {
        expect(creationKeyTypes(mode), hasLength(3));
        expect(
          creationKeyTypes(mode).where((k) => k == 'Password'),
          hasLength(1),
        );
        expect(
          creationKeyTypes(mode).where((k) => k == 'StoreKey'),
          hasLength(1),
        );
        expect(
          creationKeyTypes(mode).where((k) => k == 'RemoteKey'),
          hasLength(1),
        );
      }
    });
  });

  group('modeHasStoreKey', () {
    test('both modes have a StoreKey', () {
      expect(modeHasStoreKey(CreationMode.biometric), isTrue);
      expect(modeHasStoreKey(CreationMode.deviceStorage), isTrue);
    });
  });

  group('freshStoreKeyPersistPlan (Atonline custody alignment)', () {
    test('biometric device: enroll biometric, NO no-auth copy', () {
      final plan = freshStoreKeyPersistPlan(hasBiometric: true);
      expect(plan.enrollBiometric, isTrue);
      expect(plan.osKeystoreCopy, isFalse);
    });

    test('no biometric: no-auth copy, no biometric enrollment', () {
      final plan = freshStoreKeyPersistPlan(hasBiometric: false);
      expect(plan.enrollBiometric, isFalse);
      expect(plan.osKeystoreCopy, isTrue);
    });

    test('invariant: biometric custody and a no-auth copy are exclusive', () {
      for (final has in [true, false]) {
        final plan = freshStoreKeyPersistPlan(hasBiometric: has);
        expect(plan.enrollBiometric, isNot(plan.osKeystoreCopy));
      }
    });
  });
}
