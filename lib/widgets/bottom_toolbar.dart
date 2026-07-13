import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/design_tokens.dart';

/// Which placement tool is armed — the next tap on the page uses it.
enum ToolbarTool { signature, stamp, note }

/// Bottom action zone: a 3-way tool segment (sign/stamp/text) followed by a
/// full-width gradient send button — icon-first, big touch targets (>= 48dp).
class BottomToolbar extends StatelessWidget {
  const BottomToolbar({
    super.key,
    required this.armedTool,
    required this.enabled,
    required this.onToolSelected,
    required this.onSend,
  });

  final ToolbarTool armedTool;
  final bool enabled;
  final ValueChanged<ToolbarTool> onToolSelected;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: DesignTokens.surfaceMuted,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _ToolButton(
                  icon: Icons.draw_outlined,
                  selectedIcon: Icons.draw,
                  label: s['sign'],
                  selected: armedTool == ToolbarTool.signature,
                  enabled: enabled,
                  onPressed: () => onToolSelected(ToolbarTool.signature),
                ),
                _ToolButton(
                  icon: Icons.approval_outlined,
                  selectedIcon: Icons.approval,
                  label: s['stamp'],
                  selected: armedTool == ToolbarTool.stamp,
                  enabled: enabled,
                  onPressed: () => onToolSelected(ToolbarTool.stamp),
                ),
                _ToolButton(
                  icon: Icons.sticky_note_2_outlined,
                  selectedIcon: Icons.sticky_note_2,
                  label: s['note'],
                  selected: armedTool == ToolbarTool.note,
                  enabled: enabled,
                  onPressed: () => onToolSelected(ToolbarTool.note),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SendButton(enabled: enabled, label: s['send'], onPressed: onSend),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? DesignTokens.textFaint
        : selected
        ? DesignTokens.primaryDeep
        : DesignTokens.textMuted;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? DesignTokens.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          boxShadow: selected ? DesignTokens.shadowSm : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? selectedIcon : icon, size: 21, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width primary action — gradient pill, matches the design handoff.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? DesignTokens.primaryGradient : null,
        color: enabled ? null : DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: DesignTokens.primaryDeep.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.send_outlined,
                  size: 19,
                  color: enabled
                      ? Colors.white
                      : DesignTokens.primaryDeep.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? Colors.white
                        : DesignTokens.primaryDeep.withValues(alpha: 0.45),
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
