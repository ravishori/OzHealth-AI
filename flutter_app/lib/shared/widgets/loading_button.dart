import 'package:flutter/material.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

class LoadingButton extends StatelessWidget {
  final String text;
  final bool loading;
  final VoidCallback? onPressed;
  /// Optional background override. When null the active theme's primary is used.
  final Color? color;
  final double height;
  final IconData? trailingIcon;

  const LoadingButton({
    super.key,
    required this.text,
    required this.loading,
    this.onPressed,
    this.color,
    this.height = 52,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // When a custom color is provided, force white foreground (matches prior behaviour).
    // When null, FilledButton uses colorScheme.primary / onPrimary automatically.
    final fgColor = color != null ? Colors.white : null;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: fgColor,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: tt.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: color != null ? Colors.white : cs.onPrimary,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    Icon(trailingIcon, size: 18),
                  ],
                ],
              ),
      ),
    );
  }
}
