import 'package:flutter/material.dart';

/// 应用图标（与 iOS 桌面图标同一张图）。
///
/// 桌面图标由系统统一裁圆角，App 内部的品牌标需要自己裁，
/// 这里按 iOS 的比例（边长约 22.4%）处理，保证和桌面图标观感一致。
class BrandMark extends StatelessWidget {
  const BrandMark(this.size, {super.key, this.radius, this.shadow = true});

  final double size;

  /// 自定义圆角，默认按 iOS 图标比例推算
  final double? radius;

  /// 是否带投影；小尺寸（如标题栏 26）可以关掉
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size * 0.224;
    final borderRadius = BorderRadius.circular(r);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: size * 0.34,
                  offset: Offset(0, size * 0.12),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Image.asset(
          'assets/icon/app_icon.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
