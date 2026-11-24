@TestOn('mac-os')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:libwallet/libwallet.dart';
import 'package:tibaneapp/services/wallet/mpc_recovery_checks.dart';

void main() {
  for (final curve in ['ed25519', 'secp256k1']) {
    test(
      'native $curve recovery checks reject unusable local shares',
      () async {
        final directory = await Directory.systemTemp.createTemp('mpc-checks-');
        final binary =
            Directory(
              '${Directory.current.path}/.dart_tool/hooks_runner/shared/libwallet/build',
            ).listSync().whereType<File>().singleWhere(
              (f) => f.path.endsWith('.dylib'),
            );
        final client = LibwalletClient.initialize(
          directory.path,
          library: DynamicLibrary.open(binary.path),
        );
        addTearDown(() async {
          client.dispose();
          await directory.delete(recursive: true);
        });
        await client.ready;
        final device = await client.storeKeys.create();
        final dormant = await client.storeKeys.create();
        Wallet? created;
        // A local stand-in replaces the remote party: no live 2FA or network
        // transaction is needed to exercise the native unsealing checks.
        await for (final event in client.wallets.create(
          name: 'Synthetic recovery check',
          curve: curve,
          keys: [
            KeyDescription.storeKey(device.publicKey),
            KeyDescription.password('fixture-password'),
            KeyDescription.storeKey(dormant.publicKey),
          ],
        )) {
          if (event is Complete<Wallet>) created = event.value;
        }
        final wallet = created!;
        final firstDevice = wallet.keys.firstWhere((key) => key.isStoreKey);
        final private = firstDevice.key == device.publicKey
            ? device.privateKey
            : dormant.privateKey;
        final wrongPrivate = firstDevice.key == device.publicKey
            ? dormant.privateKey
            : device.privateKey;
        await verifyMpcLocalShares(
          client: client,
          wallet: wallet,
          devicePrivate: private,
          password: 'fixture-password',
        );
        await expectLater(
          verifyMpcLocalShares(
            client: client,
            wallet: wallet,
            devicePrivate: wrongPrivate,
            password: 'fixture-password',
          ),
          throwsA(anything),
        );
        await expectLater(
          verifyMpcLocalShares(
            client: client,
            wallet: wallet,
            devicePrivate: private,
            password: 'incorrect-password',
          ),
          throwsA(anything),
        );
        verifyMpcIdentity(wallet, wallet);
        for (final field in ['Id', 'Pubkey', 'Curve', 'Threshold']) {
          final json = wallet.toJson();
          final value = json[field];
          expect(value, isNotNull, reason: field);
          json[field] = value is int ? value + 1 : '$value-changed';
          expect(
            () => verifyMpcIdentity(wallet, Wallet.fromJson(json)),
            throwsStateError,
            reason: field,
          );
        }
        if (curve == 'ed25519') {
          final account = await client.accounts.create(
            name: 'Synthetic account',
            wallet: wallet.id,
            type: 'solana',
          );
          final replacement = await client.storeKeys.create();
          Wallet? recovered;
          await for (final event in client.wallets.reshare(
            wallet.id,
            oldKeys: [
              KeyDescription(
                id: firstDevice.id,
                type: 'StoreKey',
                key: private,
              ),
              KeyDescription(
                id: wallet.keys.firstWhere((key) => key.isPassword).id,
                type: 'Password',
                key: 'fixture-password',
              ),
            ],
            newKeys: [
              KeyDescription.storeKey(replacement.publicKey),
              KeyDescription.password('fixture-password'),
              KeyDescription.storeKey(dormant.publicKey),
            ],
          )) {
            if (event is Complete<Wallet>) recovered = event.value;
          }
          verifyMpcIdentity(wallet, recovered!);
          expect(
            recovered.keys
                .map((key) => key.id)
                .toSet()
                .intersection(wallet.keys.map((key) => key.id).toSet()),
            isEmpty,
          );
          expect(
            (await client.accounts.get(account.id)).address,
            account.address,
          );
          final recoveredDevice = recovered.keys.firstWhere(
            (key) => key.isStoreKey,
          );
          await verifyMpcLocalShares(
            client: client,
            wallet: recovered,
            devicePrivate: recoveredDevice.key == replacement.publicKey
                ? replacement.privateKey
                : dormant.privateKey,
            password: 'fixture-password',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
