import 'package:flutter_test/flutter_test.dart';
import 'package:libwallet/libwallet.dart';
import 'package:libwallet/src/client/response.dart' show LibwalletResponse;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibaneapp/services/wallet/libwallet_backend.dart';

const _password = 'synthetic-recovery-password';
const _timeout = 'reshare TSS rounds timed out after 120s';

class _Transport implements Transport {
  _Transport(this.curve);
  final String curve;
  String remote = 'crws-fixture:crwsv-original';
  int sessions = 0;
  final calls = <({String path, Map<String, dynamic>? params})>[];
  Map<String, dynamic>? ceremony;

  Wallet get wallet => Wallet(
    id: 'fixture-wallet',
    name: 'Synthetic recovery contract',
    curve: curve,
    protocol: curve == 'ed25519' ? 'frost' : 'dkls23',
    threshold: 1,
    gen: 0,
    pubkey: 'fixture-public',
    chaincode: '',
    created: DateTime.utc(2026),
    modified: DateTime.utc(2026),
    keys: [
      for (final type in ['StoreKey', 'RemoteKey', 'Password'])
        WalletKey(
          id: 'fixture-$type',
          wallet: 'fixture-wallet',
          type: type,
          key: type == 'RemoteKey' ? remote : 'fixture-$type-public',
          gen: 0,
        ),
    ],
  );

  @override
  Future<dynamic> request(
    String path,
    String verb, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((path: path, params: params));
    if (path == 'Wallet/fixture-wallet') return wallet.toJson();
    if (path == 'Account') {
      return [
        {
          'Id': 'fixture-account',
          'Wallet': wallet.id,
          'Type': curve == 'ed25519' ? 'solana' : 'ethereum',
          'Address': curve == 'ed25519'
              ? '11111111111111111111111111111111'
              : '0x0000000000000000000000000000000000000001',
          'Created': DateTime.utc(2026).toIso8601String(),
          'Updated': DateTime.utc(2026).toIso8601String(),
        },
      ];
    }
    if (path == 'Wallet/Key/fixture-Password:verify') {
      return {
        'Id': 'fixture-Password',
        'Valid': params!['Key']['Key'] == _password,
        'Checked': 'unsealed',
        'Kdf': 'argon2id',
        'KdfUpgrade': false,
      };
    }
    if (path == 'RemoteKey:reshare') {
      expect(params, {'key': remote});
      sessions++;
      return {'session': 'fixture-session-$sessions', 'length': 6};
    }
    if (path == 'RemoteKey:validate') {
      expect(params, {
        'session': 'fixture-session-$sessions',
        'code': '000000',
      });
      return {'RemoteKey': 'crws-fixture:crwsv-validated-$sessions'};
    }
    if (path == 'Wallet/fixture-wallet:repairRemoteKey') {
      expect(params, {'Key': 'crws-fixture:crwsv-validated-$sessions'});
      remote = params!['Key'] as String;
      return wallet.toJson();
    }
    if (path == 'StoreKey:create') {
      return {'private': 'synthetic-private', 'public': 'synthetic-public'};
    }
    throw StateError('Unexpected fixture request: $path');
  }

  @override
  Stream<LibwalletResponse> send(
    String path,
    String verb, [
    Map<String, dynamic>? params,
  ]) async* {
    expect(path, 'Wallet/fixture-wallet:reshare');
    expect(verb, 'POST');
    ceremony = params;
    // Stop at the native boundary: no real service, keys or ceremony run.
    throw const LibwalletException(code: '500', message: _timeout);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements LibwalletClient {
  _Client(Transport transport)
    : wallets = WalletApi(transport),
      accounts = AccountApi(transport),
      walletKeys = WalletKeyApi(transport),
      remoteKeys = RemoteKeyApi(transport),
      storeKeys = StoreKeyApi(transport);
  @override
  final WalletApi wallets;
  @override
  final AccountApi accounts;
  @override
  final WalletKeyApi walletKeys;
  @override
  final RemoteKeyApi remoteKeys;
  @override
  final StoreKeyApi storeKeys;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final curve in ['ed25519', 'secp256k1']) {
    for (final repair in [false, true]) {
      test(
        '$curve recovery follows official contract (repair: $repair)',
        () async {
          final transport = _Transport(curve);
          final backend = LibwalletBackend(client: _Client(transport));
          addTearDown(backend.dispose);
          expect(await backend.loadWalletForRecovery('fixture-wallet'), isTrue);
          if (repair) {
            final repairSession = await backend.startRemoteKeyReshare();
            expect(
              await backend.repairRemoteKeyVia2fa(
                sessionToken: repairSession!.session,
                code: '000000',
              ),
              isTrue,
            );
          }
          final session = await backend.startRemoteKeyReshare(
            password: _password,
          );
          expect(
            await backend.recoverDeviceShareVia2fa(
              sessionToken: session!.session,
              code: '000000',
              password: _password,
            ),
            isFalse,
          );
          expect(backend.error, contains(_timeout));
          expect(transport.sessions, repair ? 2 : 1);
          final freshRemote =
              'crws-fixture:crwsv-validated-${transport.sessions}';
          expect(transport.ceremony, {
            'Old': [
              {
                'Type': 'RemoteKey',
                'Key': freshRemote,
                'Id': 'fixture-RemoteKey',
              },
              {'Type': 'Password', 'Key': _password, 'Id': 'fixture-Password'},
            ],
            'New': [
              {'Type': 'StoreKey', 'Key': 'synthetic-public'},
              {'Type': 'RemoteKey', 'Key': freshRemote},
              {'Type': 'Password', 'Key': _password},
            ],
          });
          expect(
            transport.calls.where((call) => call.path == 'RemoteKey:validate'),
            hasLength(repair ? 2 : 1),
          );
        },
      );
    }
  }
}
