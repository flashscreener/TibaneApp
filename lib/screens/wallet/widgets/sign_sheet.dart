import 'package:flutter/material.dart';
import 'package:libwallet/libwallet.dart' show SigningKey, Wallet, WalletKey;

import '../../../l10n/l10n.dart';
import '../../../services/wallet/signing.dart';
import '../../../services/wallet/normal_wallet_biometrics.dart';
import '../../../services/wallet/wallet_export_format.dart'
    show isNormalMnemonicWallet;
import '../../../theme/tibane_theme.dart';
import '../../../utils/wallet_error.dart';
import '../../../widgets/gradient_button.dart';
import '../../../utils/context_extensions.dart';
import '../inapp_unlock_screen.dart';
import '../mpc_key_operation_intro_screen.dart';
import 'wallet_password_dialog.dart';

/// Per-transaction sign sheet (Atonline-parity Phase 1, §4.3).
///
/// Ported from Atonline's `DialogWalletKeysUnlock` / `WalletKeysUnlock`, as a
/// Tibane modal bottom sheet with inline English strings (D15). It collects
/// `threshold + 1` key shares for ONE signature and returns them; nothing is
/// cached beyond this sheet instance (no app-level unlock).
///
/// One tappable row per `wallet.keys`:
///  * **Password** → prompt, kept as `SigningKey(id, typedPassword, 'Password')`.
///  * **StoreKey** → resolved via [readStoreKey] (the §3.2 fallback chain:
///    biometric_storage → no-auth keystore → password blob).
///  * **RemoteKey** → omitted (recovery-only / dormant, D9).
///
/// Returns the collected `List<SigningKey>` on confirm, or `null` on cancel /
/// dismiss. [readStoreKey] receives the StoreKey [WalletKey] and the password
/// already typed in this sheet (if any, for the blob fallback step).
/// Ordinary mnemonic wallets request only their password, without a share sheet.
Future<List<SigningKey>?> showSignSheet(
  BuildContext context, {
  required Wallet wallet,
  required Future<String?> Function(WalletKey storeKey, String? password)
  readStoreKey,
  String title = 'Authorize transaction',
  String?
  subtitlePurpose, // e.g. 'sign this transaction' (default) / 'change your password'
  String actionLabel = 'Sign',
  bool transactionReviewed = false,
  bool confirmationStyle = false,
  NormalWalletBiometrics? normalBiometrics,
}) async {
  var biometricRequired = false;
  if (normalBiometrics != null && supportsNormalWalletBiometrics(wallet)) {
    try {
      biometricRequired = await normalBiometrics.isEnabled(wallet);
    } catch (_) {
      biometricRequired = true;
    }
  }
  if (!context.mounted) return null;
  if (biometricRequired) {
    if (!context.mounted) return null;
    SigningKey? key;
    try {
      key = await normalBiometrics!.readSigningKey(
        wallet,
        NormalBiometricPrompt(
          context.l10n.normalBiometricsAuthorize,
          context.l10n.actionCancel,
        ),
      );
    } catch (_) {
      // Cancellation never falls through to an unprotected device-key read.
    }
    if (!context.mounted) return null;
    if (key != null) return [key];
    if (!isNormalMnemonicWallet(wallet)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.normalBiometricsPrivateKeyFailed),
          duration: const Duration(seconds: 3),
        ),
      );
      return null;
    }
    // Recovery words remain password-protected; biometrics are optional.
  }
  if (transactionReviewed && isSingleDeviceKeyWallet(wallet)) {
    try {
      final key = wallet.keys.single;
      final secret = await readStoreKey(key, null);
      if (!context.mounted) return null;
      if (secret == null || secret.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.signSheetDeviceKeyError),
            duration: const Duration(seconds: 3),
          ),
        );
        return null;
      }
      return [SigningKey(id: key.id, key: secret, type: 'StoreKey')];
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(walletErrorMessageForContext(context, error)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }
  if (isNormalMnemonicWallet(wallet)) {
    final password = await showWalletPasswordDialog(
      context,
      confirmationTitle: confirmationStyle ? title : null,
    );
    if (!context.mounted || password == null || password.isEmpty) return null;
    return [
      SigningKey(id: wallet.keys.single.id, key: password, type: 'Password'),
    ];
  }
  var recoveryRequested = false;
  final keys = await showModalBottomSheet<List<SigningKey>>(
    context: context,
    backgroundColor: TibaneColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SignSheet(
      wallet: wallet,
      readStoreKey: readStoreKey,
      title: title,
      subtitlePurpose: subtitlePurpose ?? 'sign this transaction',
      actionLabel: actionLabel,
      confirmationStyle: confirmationStyle,
      onRecoverDevice: () {
        recoveryRequested = true;
      },
    ),
  );
  if (recoveryRequested && context.mounted) {
    final confirmed = await showMpcActivationWarning(context);
    if (confirmed && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              InAppUnlockScreen(walletId: wallet.id, startActivation: true),
        ),
      );
    }
    // Recovery rotates the shares. Never resume a pending signature with old keys.
    return null;
  }
  return keys;
}

class _SignSheet extends StatefulWidget {
  const _SignSheet({
    required this.wallet,
    required this.readStoreKey,
    required this.title,
    required this.subtitlePurpose,
    required this.actionLabel,
    required this.confirmationStyle,
    required this.onRecoverDevice,
  });

  final Wallet wallet;
  final Future<String?> Function(WalletKey storeKey, String? password)
  readStoreKey;
  final String title;
  final String subtitlePurpose;
  final String actionLabel;
  final bool confirmationStyle;
  final VoidCallback onRecoverDevice;

  @override
  State<_SignSheet> createState() => _SignSheetState();
}

class _SignSheetState extends State<_SignSheet> {
  final List<SigningKey> _collected = [];
  String? _password; // typed once, reused for the StoreKey blob fallback
  String? _storeKeyPriv; // cached so a re-tap doesn't re-prompt biometric
  bool _busy = false;
  String? _error;
  bool _deviceKeyUnavailable = false;

  Wallet get _wallet => widget.wallet;
  int get _required => requiredSigningShares(_wallet.threshold);
  bool get _ready => signSheetReady(_collected.length, _wallet.threshold);

  bool _isUnlocked(WalletKey key) => _collected.any((k) => k.id == key.id);

  Future<void> _unlock(WalletKey key) async {
    if (_busy || _isUnlocked(key) || key.isRemoteKey) return;
    setState(() {
      _error = null;
      _deviceKeyUnavailable = false;
    });

    if (key.isPassword) {
      // Reuse the password already typed this sheet, so a D5 wallet's two
      // Password shares only prompt once.
      var pwd = _password;
      if (pwd == null) {
        pwd = await showWalletPasswordDialog(context);
        if (!mounted || pwd == null || pwd.isEmpty) return;
      }
      final entered = pwd;
      setState(() {
        _password = entered;
        _collected.add(SigningKey(id: key.id, key: entered, type: 'Password'));
      });
      return;
    }

    if (key.isStoreKey) {
      setState(() => _busy = true);
      try {
        final priv = _storeKeyPriv ?? await widget.readStoreKey(key, _password);
        if (!mounted) return;
        if (priv == null || priv.isEmpty) {
          debugPrint(
            '[signSheet] StoreKey ${key.id} unreadable on this device '
            '(biometric/keystore/blob all empty)',
          );
          setState(() {
            _error = context.l10n.signSheetDeviceKeyError;
            _deviceKeyUnavailable = true;
          });
          return;
        }
        setState(() {
          _storeKeyPriv = priv;
          _collected.add(SigningKey(id: key.id, key: priv, type: 'StoreKey'));
        });
      } catch (e) {
        debugPrint('[signSheet] device key unlock failed: $e');
        setState(() => _error = walletErrorMessageForContext(context, e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final displayKeys = [
      ..._wallet.keys.where((key) => key.isStoreKey),
      ..._wallet.keys.where((key) => key.isPassword),
      ..._wallet.keys.where(
        (key) => !key.isRemoteKey && !key.isStoreKey && !key.isPassword,
      ),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: TibaneColors.textDim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.title, style: context.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              l10n.signSheetUnlockHint(
                _required.toString(),
                widget.subtitlePurpose,
              ),
              style: const TextStyle(color: TibaneColors.textMuted),
            ),
            const SizedBox(height: 16),
            for (final key in displayKeys) _keyRow(key, l10n),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: TibaneColors.error, fontSize: 13),
              ),
              if (_deviceKeyUnavailable &&
                  _wallet.keys.any((key) => key.isRemoteKey)) ...[
                const SizedBox(height: 12),
                GradientButton(
                  key: const Key('sign-recover-device'),
                  label: l10n.inappUnlockSetupTitle,
                  expanded: true,
                  onPressed: _busy
                      ? null
                      : () {
                          widget.onRecoverDevice();
                          Navigator.of(context).pop();
                        },
                ),
              ],
            ],
            const SizedBox(height: 12),
            Text(
              l10n.signSheetKeysUnlocked(
                _collected.length.toString(),
                _required.toString(),
              ),
              style: const TextStyle(color: TibaneColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.confirmationStyle)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: TibaneColors.orange,
                      foregroundColor: TibaneColors.black,
                    ),
                    onPressed: _ready && !_busy
                        ? () => Navigator.pop(context, _collected)
                        : null,
                    child: Text(widget.actionLabel),
                  )
                else
                  GradientButton(
                    label: widget.actionLabel,
                    expanded: true,
                    onPressed: _ready && !_busy
                        ? () => Navigator.pop(context, _collected)
                        : null,
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  style: widget.confirmationStyle
                      ? TextButton.styleFrom(
                          backgroundColor: TibaneColors.surface,
                          foregroundColor: TibaneColors.text,
                        )
                      : null,
                  child: Text(l10n.actionCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyRow(WalletKey key, AppLocalizations l10n) {
    final unlocked = _isUnlocked(key);
    final loading = _busy && key.isStoreKey && !unlocked;
    final subtitle = key.isStoreKey
        ? l10n.signSheetKeyDevice
        : l10n.signSheetPasswordTitle;
    final title = key.isStoreKey
        ? l10n.signSheetDeviceTitle
        : key.isPassword
        ? l10n.labelPassword
        : key.type;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TibaneColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unlocked ? TibaneColors.orange : TibaneColors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          key: ValueKey('sign-share-${key.id}'),
          onTap: (unlocked || _busy) ? null : () => _unlock(key),
          leading: Semantics(
            checked: unlocked,
            child: loading
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TibaneColors.orange,
                    ),
                  )
                : Icon(
                    unlocked
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 26,
                    color: unlocked
                        ? TibaneColors.orange
                        : TibaneColors.textMuted,
                  ),
          ),
          title: Text(title),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: TibaneColors.textMuted, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
