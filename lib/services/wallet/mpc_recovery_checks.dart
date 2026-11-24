import 'package:libwallet/libwallet.dart';

void verifyMpcIdentity(Wallet before, Wallet after) {
  if (before.id != after.id ||
      before.pubkey != after.pubkey ||
      before.curve != after.curve ||
      before.threshold != after.threshold) {
    throw StateError('Wallet recovery changed wallet identity');
  }
}

/// Opening both local shares is required; metadata or file presence is not
/// proof that the restored device can sign.
Future<void> verifyMpcLocalShares({
  required LibwalletClient client,
  required Wallet wallet,
  required String devicePrivate,
  required String password,
}) async {
  final device = wallet.keys.firstWhere((key) => key.isStoreKey);
  final passwords = wallet.keys.where((key) => key.isPassword).toList();
  if (passwords.isEmpty) throw StateError('Wallet has no Password share');
  final deviceCheck = await client.walletKeys.verify(
    device.id,
    key: KeyDescription.storeKey(devicePrivate),
  );
  if (!deviceCheck.valid) {
    throw StateError('Recovered device share could not be verified');
  }
  for (final key in passwords) {
    final check = await client.walletKeys.verify(
      key.id,
      key: KeyDescription.password(password),
    );
    if (!check.valid) {
      throw StateError('Recovered password share could not be verified');
    }
  }
}
