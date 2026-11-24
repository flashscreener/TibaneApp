import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/tibane_theme.dart';

enum WalletActionIcon {
  send('wallet-send'),
  receive('wallet-receive'),
  swap('wallet-swap');

  const WalletActionIcon(this.asset);

  final String asset;
}

/// Shared wallet action used by the dashboard and token detail screens.
class WalletActionButton extends StatelessWidget {
  final WalletActionIcon icon;
  final String label;
  final VoidCallback? onTap;

  const WalletActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = enabled
        ? TibaneColors.orange.withValues(alpha: 0.9)
        : TibaneColors.textDim;

    return Expanded(
      child: Material(
        color: TibaneColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.only(top: 8, bottom: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TibaneColors.border),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 36.25,
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/icons/${icon.asset}.svg',
                      width: 33.75,
                      height: 33.75,
                      colorFilter: ColorFilter.mode(
                        foreground,
                        BlendMode.srcIn,
                      ),
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? Color.lerp(
                            TibaneColors.textMuted,
                            TibaneColors.text,
                            0.19,
                          )
                        : TibaneColors.textDim,
                    fontSize: 16.24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
