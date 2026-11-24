import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tibaneapp/l10n/l10n.dart';
import 'package:tibaneapp/screens/wallet/mpc_wallet_intro_screen.dart';
import 'package:tibaneapp/theme/tibane_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final contactWords = {
    'en': RegExp('email|phone|contact'),
    'pt': RegExp('e-mail|celular|contato'),
    'fr': RegExp('e-mail|téléphone|contact'),
    'ja': RegExp('登録'),
  };
  const codeWords = {'en': 'code', 'pt': 'código', 'fr': 'code', 'ja': 'コード'};
  for (final locale in AppLocalizations.supportedLocales) {
    final language = locale.languageCode;
    test('standard MPC restore requirements are explicit in $language', () {
      final strings =
          jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final key in [
        'mpcIntroRestoreBody',
        'inappCreateIdentifierRestoreBody',
        'postCreateBackupBody',
        'exportJsonHint',
        'backupRestoreHint',
        'helpFaqRestoreHowA',
        'helpFaqRestoredCantSendA',
        'helpFaqLostMpcContactA',
        'walletResetStepThreeBody',
      ]) {
        expect(strings[key], contains(codeWords[language]!), reason: key);
        expect(strings[key], contains(contactWords[language]!), reason: key);
      }
      expect(strings['mpcIntroSplitBody'], contains('\n\n'));
      expect(strings['postCreateBackupBody'], contains('\n\n'));
    });

    for (final size in [const Size(320, 568), const Size(393, 852)]) {
      testWidgets('four MPC introduction pages fit in $language at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: TibaneTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const MpcWalletIntroScreen(),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = tester.element(find.byType(MpcWalletIntroScreen)).l10n;
        final pages = [
          (l10n.mpcIntroSplitTitle, l10n.mpcIntroSplitBody, null),
          (
            l10n.mpcIntroPhraseTitle,
            l10n.mpcIntroPhraseBody,
            l10n.mpcIntroPhraseEmphasis,
          ),
          (
            l10n.mpcIntroSecurityTitle,
            l10n.mpcIntroSecurityBody,
            l10n.mpcIntroSecurityEmphasis,
          ),
          (
            l10n.mpcIntroRestoreTitle,
            l10n.mpcIntroRestoreBody,
            l10n.mpcIntroRestoreEmphasis,
          ),
        ];
        for (var i = 0; i < pages.length; i++) {
          final (title, body, emphasis) = pages[i];
          expect(find.text(title), findsOneWidget);
          final paragraph = emphasis == null ? body : '$body\n\n$emphasis';
          expect(find.text(paragraph, findRichText: true), findsOneWidget);
          final next = find.byKey(const Key('mpc-intro-next'));
          expect(next.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (i < pages.length - 1) {
            await tester.tap(next);
            await tester.pumpAndSettle();
          }
        }
      });
    }
  }
}
