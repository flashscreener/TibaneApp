/// Wallet-creation decisions and device-share custody.
///
/// Kept out of the backend so they're unit-testable without a device, a
/// libwallet client, or a biometric prompt (the existing pure-decision
/// pattern). The keygen ceremony, the biometric enrollment prompt, and the
/// at-rest writes are device-verified.
library;

/// Debug override for exercising OS-keystore custody without biometrics.
/// The standard three independent shares are retained in either mode.
///   flutter run --dart-define=FORCE_UNSAFE=true
const bool kForceUnsafeCreation = bool.fromEnvironment('FORCE_UNSAFE');

/// The committee shape + StoreKey custody for a newly created wallet.
enum CreationMode {
  /// Biometric device: committee `[StoreKey, RemoteKey, Password]`; the
  /// StoreKey private is custodied behind `biometric_storage` (+ the D8
  /// password blob). No no-auth keystore copy.
  biometric,

  /// No biometric: retain an independent device key in the OS keystore.
  /// Never replace it with a second share derived from the same password.
  deviceStorage,
}

/// Pick the creation mode. Biometric custody is used (and enforced) whenever
/// the device has biometrics, unless [forceUnsafe] (a debug override) is set.
CreationMode creationModeFor({
  required bool hasBiometric,
  bool forceUnsafe = false,
}) => (hasBiometric && !forceUnsafe)
    ? CreationMode.biometric
    : CreationMode.deviceStorage;

/// The committee key types, in order, for a creation mode. Used to build the
/// `KeyDescription` list; unit-tested without libwallet.
List<String> creationKeyTypes(CreationMode mode) => switch (mode) {
  CreationMode.biometric => const ['StoreKey', 'RemoteKey', 'Password'],
  CreationMode.deviceStorage => const ['StoreKey', 'RemoteKey', 'Password'],
};

/// Both creation modes preserve the standard device/password/remote layout.
bool modeHasStoreKey(CreationMode mode) => true;

/// How to persist a **freshly-minted StoreKey** (creation, rotate, 2FA
/// recovery, device-import) so custody stays consistent — the Atonline model:
///
/// - On a biometric device the StoreKey private is custodied **only** behind
///   `biometric_storage` (so every sign prompts), plus the D8 password blob for
///   OS-restore recovery. There is **no** no-auth keystore copy — [enrollBiometric]
///   is true, [osKeystoreCopy] false.
/// - Without biometric it falls back to the no-auth OS keystore copy (+ blob) —
///   [enrollBiometric] false, [osKeystoreCopy] true.
///
/// The invariant: `enrollBiometric == !osKeystoreCopy` — biometric custody and
/// a no-auth copy are mutually exclusive, so nothing ever bypasses the gate.
({bool enrollBiometric, bool osKeystoreCopy}) freshStoreKeyPersistPlan({
  required bool hasBiometric,
}) => (enrollBiometric: hasBiometric, osKeystoreCopy: !hasBiometric);
