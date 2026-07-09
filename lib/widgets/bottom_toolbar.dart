import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Which placement tool is armed — the next tap on the page uses it.
enum ToolbarTool { signature, stamp, note }

/// Fixed bottom bar: sign · stamp · note · send. Icon-first, big touch
/// targets (>= 48dp), evenly spaced.
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
    return SizedBox(
      height: 76,
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
              _ToolButton(
                icon: Icons.send_outlined,
                selectedIcon: Icons.send,
                label: s['send'],
                selected: false,
                enabled: enabled,
                emphasized: true,
                onPressed: onSend,
              ),
            ],
      ),
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
    this.emphasized = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool enabled;
  final bool emphasized;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? scheme.onSurface.withValues(alpha: 0.35)
        : emphasized
            ? scheme.primary
            : selected
                ? scheme.primary
                : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(selected ? selectedIcon : icon,
                  size: 26, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
