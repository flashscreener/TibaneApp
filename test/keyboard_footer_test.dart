import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibaneapp/l10n/gen/app_localizations.dart';
import 'package:tibaneapp/main.dart';
import 'package:tibaneapp/screens/wallet/create_seed_wallet_screen.dart';
import 'package:tibaneapp/screens/wallet/inapp_create_screen.dart';
import 'package:tibaneapp/screens/wallet/wallet_welcome_screen.dart';
import 'package:tibaneapp/services/uk_compliance_service.dart';
import 'package:tibaneapp/services/wallet/libwallet_backend.dart';
import 'package:tibaneapp/services/wallet_service.dart';
import 'package:tibaneapp/theme/tibane_theme.dart';

class _Backend extends LibwalletBackend {
  @override
  Future<bool> needsBiometricMigration() async => false;
}

class _Wallet extends WalletService {
  final backend = _Backend();
  @override
  LibwalletBackend get libwallet => backend;
  @override
  bool get dataReady => true;
  @override
  Future<void> reportLifecycle(String status) async {}
  @override
  void dispose() {
    backend.dispose();
    super.dispose();
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final name in [
      'com.llfbandit.app_links/messages',
      'com.llfbandit.app_links/events',
      'plugins.flutter.io/local_auth',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(name),
            (call) async => name == 'plugins.flutter.io/local_auth'
                ? (call.method == 'getAvailableBiometrics' ? <String>[] : false)
                : null,
          );
    }
  });
  tearDown(() {
    for (final name in [
      'com.llfbandit.app_links/messages',
      'com.llfbandit.app_links/events',
      'plugins.flutter.io/local_auth',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  for (final (name, page) in <(String, Widget)>[
    ('seed', const CreateSeedWalletScreen()),
    ('MPC', const InAppCreateScreen()),
  ]) {
    for (final bottomPadding in [0.0, 34.0]) {
      testWidgets(
        '$name footer stays stable across keyboard dismissal ($bottomPadding)',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.viewPadding = FakeViewPadding(
            top: 44,
            bottom: bottomPadding,
          );
          tester.view.padding = FakeViewPadding(top: 44, bottom: bottomPadding);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.view.resetViewPadding);
          addTearDown(tester.view.resetPadding);
          final wallet = _Wallet();
          final compliance = UkComplianceService();
          addTearDown(wallet.dispose);
          addTearDown(compliance.dispose);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<WalletService>.value(value: wallet),
                ChangeNotifierProvider<UkComplianceService>.value(
                  value: compliance,
                ),
              ],
              child: MaterialApp(
                theme: TibaneTheme.darkTheme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const TibaneShell(forceSeeker: false),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final navigator = Navigator.of(
            tester.element(find.byType(WalletWelcomeScreen)),
          );
          navigator.push(MaterialPageRoute<void>(builder: (_) => page));
          await tester.pumpAndSettle();
          final footer = find.byType(BottomNavigationBar);
          final element = tester.element(footer);
          final rect = tester.getRect(footer);
          await tester.tap(find.byType(TextField).first);
          await tester.pump();
          final button = name == 'seed'
              ? find.byKey(const Key('seed-create-generate'))
              : find.text('Send verification code');
          Rect? settledButton;
          for (final inset in [300.0, 180.0, 90.0, 40.0, 10.0, 1.0, 0.0]) {
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            tester.view.padding = FakeViewPadding(
              top: 44,
              bottom: inset > 0 ? 0 : bottomPadding,
            );
            if (inset == 0) {
              await tester.testTextInput.receiveAction(TextInputAction.done);
            }
            await tester.pump(const Duration(milliseconds: 16));
            expect(footer, findsOneWidget);
            expect(tester.element(footer), same(element));
            expect(tester.getRect(footer), rect);
            // Once the keyboard is below the footer, the form's geometry must
            // not jump again when its inset reaches exactly zero.
            if (inset <= 40) {
              final current = tester.getRect(button);
              settledButton ??= current;
              expect(current, settledButton);
            }
            expect(tester.takeException(), isNull);
          }
          await tester.pumpAndSettle();
          expect(tester.getRect(footer), rect);
          expect(tester.getRect(button), settledButton);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
