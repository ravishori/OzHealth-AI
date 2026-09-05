import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Circular avatar that shows a network image when available, or
/// falls back to initials derived from [name].
class UserAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final TextStyle? initialsStyle;

  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24,
    this.backgroundColor,
    this.initialsStyle,
  });

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+'));
    return words.take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Theme.of(context).colorScheme.primary;
    final diameter = radius * 2;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg.withValues(alpha: 0.15),
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl!,
                width: diameter,
                height: diameter,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallback(bg),
              ),
            )
          : _fallback(bg),
    );
  }

  Widget _fallback(Color bg) => Center(
        child: Text(
          _initials,
          style: initialsStyle ??
              TextStyle(
                fontSize: radius * 0.6,
                fontWeight: FontWeight.bold,
                color: bg,
              ),
        ),
      );
}
