import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/delivery.dart';

/// Product picture of a stop.
///
/// The photo comes from the API (`item.imageUrl`); while it loads, when the
/// backend does not send one, or when the request fails, a neutral parcel
/// placeholder with the same size is shown so the layout never jumps.
class ItemImage extends StatelessWidget {
  const ItemImage({
    super.key,
    required this.item,
    this.width = 56,
    this.height = 56,
    this.radius = 16,
    this.iconSize = 22,
  });

  final DeliveryItem? item;
  final double width;
  final double height;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final fallback = _Placeholder(
      width: width,
      height: height,
      radius: radius,
      iconSize: iconSize,
    );
    final loading = _Placeholder(
      width: width,
      height: height,
      radius: radius,
      iconSize: iconSize,
      showProgress: true,
    );

    final remote = item?.hasImage ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: !remote
            ? fallback
            : Image.network(
                item!.imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : loading,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.width,
    required this.height,
    required this.radius,
    required this.iconSize,
    this.showProgress = false,
  });

  final double width;
  final double height;
  final double radius;
  final double iconSize;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: showProgress
          ? SizedBox(
              width: iconSize,
              height: iconSize,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.inkMuted,
              ),
            )
          : Icon(Icons.inventory_2_outlined, size: iconSize, color: AppTheme.inkMuted),
    );
  }
}
