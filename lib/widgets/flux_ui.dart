import 'package:flutter/material.dart';
import 'package:neopop/neopop.dart';

import '../core/theme.dart';

enum FluxButtonTone { primary, success, danger, neutral }

class FluxButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final FluxButtonTone tone;
  final bool outlined;
  final bool fullWidth;
  final EdgeInsetsGeometry padding;

  const FluxButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tone = FluxButtonTone.primary,
    this.outlined = false,
    this.fullWidth = true,
    this.padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  });

  Color get _fillColor {
    switch (tone) {
      case FluxButtonTone.success:
        return AppTheme.success;
      case FluxButtonTone.danger:
        return AppTheme.error;
      case FluxButtonTone.neutral:
        return AppTheme.bgCardElevated;
      case FluxButtonTone.primary:
        return AppTheme.accent;
    }
  }

  Color get _foregroundColor {
    if (AppTheme.isNeoPop) {
      return outlined || tone == FluxButtonTone.neutral
          ? AppTheme.textPrimary
          : Colors.black;
    }
    return Colors.white;
  }

  Color get _borderColor {
    switch (tone) {
      case FluxButtonTone.success:
        return AppTheme.success;
      case FluxButtonTone.danger:
        return AppTheme.error;
      case FluxButtonTone.neutral:
        return AppTheme.border;
      case FluxButtonTone.primary:
        return AppTheme.accent;
    }
  }

  Widget _material(BuildContext context) {
    final content = DefaultTextStyle(
      style: Theme.of(context).textTheme.labelLarge!.copyWith(
        color: _foregroundColor,
        fontWeight: FontWeight.w700,
      ),
      child: IconTheme(
        data: IconThemeData(color: _foregroundColor, size: 18),
        child: Padding(
          padding: padding,
          child: Center(child: child),
        ),
      ),
    );

    final elevatedStyle = Theme.of(context).elevatedButtonTheme.style?.copyWith(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final outlinedStyle = Theme.of(context).outlinedButtonTheme.style?.copyWith(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final button = outlined
        ? OutlinedButton(
            onPressed: onPressed,
            style: outlinedStyle,
            child: content,
          )
        : ElevatedButton(
            onPressed: onPressed,
            style: elevatedStyle,
            child: content,
          );
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _neoPop(BuildContext context) {
    final content = DefaultTextStyle(
      style: Theme.of(context).textTheme.labelLarge!.copyWith(
        color: _foregroundColor,
        fontWeight: FontWeight.w700,
      ),
      child: IconTheme(
        data: IconThemeData(color: _foregroundColor, size: 18),
        child: Padding(
          padding: padding,
          child: Center(child: child),
        ),
      ),
    );

    final button = NeoPopButton(
      color: outlined ? AppTheme.bgCard : _fillColor,
      buttonPosition: Position.center,
      parentColor: AppTheme.bg,
      grandparentColor: AppTheme.bg,
      border: Border.all(color: _borderColor, width: 1),
      onTapUp: onPressed,
      child: content,
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.isNeoPop ? _neoPop(context) : _material(context);
  }
}

class FluxSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  const FluxSurface({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = color ?? AppTheme.bgCard;
    final stroke = borderColor ?? AppTheme.border;
    final wrappedChild = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (AppTheme.isNeoPop) {
      return NeoPopCard(
        color: surfaceColor,
        borderColor: stroke,
        child: wrappedChild,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: borderRadius ?? AppTheme.cardBorderRadius,
        border: Border.all(color: stroke),
      ),
      child: wrappedChild,
    );
  }
}
