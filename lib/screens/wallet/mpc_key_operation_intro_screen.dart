import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/tibane_theme.dart';
import '../../widgets/gradient_button.dart';
import 'post_create_backup_screen.dart';

enum MpcKeyOperation { activation, resetDeviceKey }

Future<bool> showMpcActivationWarning(BuildContext context) =>
    showMpcKeyOperationIntro(context, MpcKeyOperation.activation);

Future<bool> showMpcKeyOperationIntro(
  BuildContext context,
  MpcKeyOperation operation,
) async {
  FocusScope.of(context).unfocus();
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MpcKeyOperationIntroScreen(operation: operation),
        ),
      ) ==
      true;
}

class MpcKeyOperationIntroScreen extends StatefulWidget {
  const MpcKeyOperationIntroScreen({super.key, required this.operation});

  final MpcKeyOperation operation;

  @override
  State<MpcKeyOperationIntroScreen> createState() =>
      _MpcKeyOperationIntroScreenState();
}

class _MpcKeyOperationIntroScreenState
    extends State<MpcKeyOperationIntroScreen> {
  int _step = 0;

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop(false);
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activation = widget.operation == MpcKeyOperation.activation;
    final titles = activation
        ? [l10n.mpcActivationIntroTitle, l10n.mpcActivationRequirementsTitle]
        : [l10n.mpcDeviceResetIntroTitle, l10n.mpcDeviceResetRequirementsTitle];
    final bodies = activation
        ? [l10n.mpcActivationIntroBody, l10n.mpcActivationRequirementsBody]
        : [l10n.mpcDeviceResetIntroBody, l10n.mpcDeviceResetRequirementsBody];
    final last = _step == 2;
    return PopScope<bool>(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: TibaneColors.black,
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.actionBack,
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: _back,
          ),
          title: Text(
            activation
                ? l10n.inappUnlockSetupTitle
                : l10n.securityResetDeviceKeyTitle,
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Semantics(
                  label: l10n.mpcIntroProgress(_step + 1, 3),
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= _step
                                  ? TibaneColors.orange
                                  : TibaneColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (last)
                Expanded(
                  child: MpcActivationWarningScreen(
                    body: activation
                        ? null
                        : l10n.mpcDeviceResetBackupWarningBody,
                  ),
                )
              else ...[
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey(_step),
                    padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                    child: Column(
                      children: [
                        Icon(
                          _step == 0
                              ? (activation
                                    ? Icons.phonelink_lock_outlined
                                    : Icons.refresh)
                              : Icons.verified_user_outlined,
                          size: 64,
                          color: TibaneColors.orange,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          titles[_step],
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontSize: 27.6,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          bodies[_step],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: TibaneColors.textMuted,
                            fontSize: 18,
                            height: 1.55,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GradientButton(
                        key: const Key('mpc-key-operation-next'),
                        label: l10n.actionNext,
                        expanded: true,
                        onPressed: () => setState(() => _step++),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('mpc-key-operation-back'),
                        onPressed: _back,
                        style: TextButton.styleFrom(
                          backgroundColor: TibaneColors.surface,
                          foregroundColor: TibaneColors.textMuted,
                        ),
                        child: Text(
                          _step == 0 ? l10n.actionCancel : l10n.actionBack,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
