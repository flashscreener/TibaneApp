import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libwallet/libwallet.dart';
import 'package:provider/provider.dart';
import 'package:tibaneapp/l10n/gen/app_localizations.dart';
import 'package:tibaneapp/screens/settings/security_privacy_screen.dart';
import 'package:tibaneapp/screens/wallet/mpc_key_operation_intro_screen.dart';
import 'package:tibaneapp/services/wallet/accounts_service.dart';
import 'package:tibaneapp/services/wallet/libwallet_backend.dart';
import 'package:tibaneapp/services/wallet_service.dart';
import 'package:tibaneapp/theme/tibane_theme.dart';

class _Backend extends LibwalletBackend {
  bool loaded = true;
  @override
  bool get hasWallet => loaded;
  @override
  String get walletId => 'fixture';
}

class _Accounts extends ChangeNotifier implements AccountsService {
  String protocol = 'frost';
  @override
  Map<String, Wallet> get walletsById => {
    'fixture': Wallet(
      id: 'fixture',
      name: 'Fixture',
      curve: 'ed25519',
      protocol: protocol,
      threshold: protocol == 'frost' ? 1 : 0,
      gen: 0,
      pubkey: 'public',
      chaincode: '',
      created: DateTime.utc(2026),
      modified: DateTime.utc(2026),
      keys: [
        for (final type
            in protocol == 'mnemonic'
                ? ['Password']
                : protocol == 'private-key'
                ? ['StoreKey']
                : ['StoreKey', 'Password', 'RemoteKey'])
          WalletKey(
            id: type,
            wallet: 'fixture',
            type: type,
            key: 'public',
            gen: 0,
          ),
      ],
    ),
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends WalletService {
  final backend = _Backend();
  final fixtureAccounts = _Accounts();
  @override
  WalletKind get kind => WalletKind.inapp;
  @override
  LibwalletBackend get libwallet => backend;
  @override
  AccountsService get accountsService => fixtureAccounts;

  void useNormalWallet(String protocol) {
    fixtureAccounts.protocol = protocol;
    notifyListeners();
  }

  @override
  void dispose() {
    backend.dispose();
    fixtureAccounts.dispose();
    super.dispose();
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final language in ['en', 'pt', 'fr', 'ja']) {
    for (final operation in MpcKeyOperation.values) {
      for (final width in [320.0, 414.0]) {
        testWidgets('$operation three-step guidance $language width $width', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width * 2, 896 * 2);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          bool? accepted;
          await tester.pumpWidget(
            MaterialApp(
              theme: TibaneTheme.darkTheme,
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Open fixture'),
                    onPressed: () async => accepted =
                        await showMpcKeyOperationIntro(context, operation),
                  ),
                ),
              ),
            ),
          );
          await _tap(tester, find.text('Open fixture'));
          final l10n = AppLocalizations.of(
            tester.element(find.byType(MpcKeyOperationIntroScreen)),
          );
          final firstTitle = operation == MpcKeyOperation.activation
              ? l10n.mpcActivationIntroTitle
              : l10n.mpcDeviceResetIntroTitle;
          expect(find.text(firstTitle), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(TextField), findsNothing);
          expect(accepted, isNull);
          final next = find.byKey(const Key('mpc-key-operation-next'));
          await _tap(tester, next);
          await _tap(tester, find.byKey(const Key('mpc-key-operation-back')));
          expect(find.text(firstTitle), findsOneWidget);
          await _tap(tester, next);
          await _tap(tester, next);
          expect(
            find.text(l10n.mpcActivationBackupWarningTitle),
            findsOneWidget,
          );
          expect(
            find.text(
              operation == MpcKeyOperation.activation
                  ? l10n.mpcActivationBackupWarningBody
                  : l10n.mpcDeviceResetBackupWarningBody,
            ),
            findsOneWidget,
          );
          expect(accepted, isNull);
          await _tap(tester, find.text(l10n.actionConfirm));
          expect(accepted, isTrue);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final reset in [false, true]) {
    testWidgets(
      'settings opens ${reset ? 'device reset' : 'activation'} guidance before authentication',
      (tester) async {
        final service = _Service();
        addTearDown(service.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<WalletService>.value(
            value: service,
            child: MaterialApp(
              theme: TibaneTheme.darkTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const SecurityPrivacyScreen(),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SecurityPrivacyScreen)),
        );
        await _tap(tester, find.byKey(const Key('mpc-wallet-settings-entry')));
        await _tap(
          tester,
          find.text(
            reset
                ? l10n.securityResetDeviceKeyTitle
                : l10n.securitySetUpSigningTitle,
          ),
        );
        expect(find.byType(MpcKeyOperationIntroScreen), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(TextField), findsNothing);
        for (var i = 0; i < 2; i++) {
          await _tap(tester, find.byKey(const Key('mpc-key-operation-next')));
        }
        await _tap(tester, find.text(l10n.actionCancel));
        expect(find.byType(MpcKeyOperationIntroScreen), findsNothing);
        expect(find.byType(MpcWalletSettingsScreen), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(SecurityPrivacyScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['en', 'pt', 'fr', 'ja']) {
    testWidgets('MPC operations are grouped in a submenu in $language', (
      tester,
    ) async {
      final service = _Service();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<WalletService>.value(
          value: service,
          child: MaterialApp(
            theme: TibaneTheme.darkTheme,
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SecurityPrivacyScreen(),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SecurityPrivacyScreen)),
      );
      final titles = [
        l10n.securityChangePasswordTitle,
        l10n.securityResetDeviceKeyTitle,
        l10n.securityReset2faTitle,
        l10n.securitySetUpSigningTitle,
        l10n.securityCloudBackupTitle,
      ];
      for (final title in titles) {
        expect(find.text(title), findsNothing);
      }
      await _tap(tester, find.byKey(const Key('mpc-wallet-settings-entry')));
      for (final title in titles) {
        expect(find.text(title), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final protocol in ['mnemonic', 'private-key']) {
    testWidgets('$protocol wallet cannot open MPC settings', (tester) async {
      final service = _Service()..useNormalWallet(protocol);
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<WalletService>.value(
          value: service,
          child: MaterialApp(
            theme: TibaneTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SecurityPrivacyScreen(),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SecurityPrivacyScreen)),
      );
      await _tap(tester, find.byKey(const Key('mpc-wallet-settings-entry')));
      expect(find.byType(MpcWalletSettingsScreen), findsNothing);
      expect(find.text(l10n.securityMpcWalletsOnly), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text(l10n.securityMpcWalletsOnly), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'MPC submenu blocks actions if the active wallet changes to seed',
    (tester) async {
      final service = _Service();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<WalletService>.value(
          value: service,
          child: MaterialApp(
            theme: TibaneTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SecurityPrivacyScreen(),
          ),
        ),
      );
      await _tap(tester, find.byKey(const Key('mpc-wallet-settings-entry')));
      service.useNormalWallet('mnemonic');
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MpcWalletSettingsScreen)),
      );
      for (final key in [
        'mpc-change-password',
        'mpc-reset-device-key',
        'mpc-reset-2fa',
        'mpc-set-up-signing',
        'mpc-cloud-backup',
      ]) {
        await _tap(tester, find.byKey(Key(key)));
        expect(find.text(l10n.securityMpcWalletsOnly), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(MpcKeyOperationIntroScreen), findsNothing);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('MPC cloud restore remains accessible without a loaded wallet', (
    tester,
  ) async {
    final service = _Service();
    service.backend.loaded = false;
    addTearDown(service.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<WalletService>.value(
        value: service,
        child: MaterialApp(
          theme: TibaneTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SecurityPrivacyScreen(),
        ),
      ),
    );
    await _tap(tester, find.byKey(const Key('mpc-wallet-settings-entry')));
    expect(find.byType(MpcWalletSettingsScreen), findsOneWidget);
    final cloud = find.byKey(const Key('mpc-cloud-backup'));
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: cloud, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
  });
}
