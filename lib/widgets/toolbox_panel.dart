import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../screens/history_screen.dart';
import '../screens/settings_screen.dart';
import '../services/history_service.dart';
import '../theme/design_tokens.dart';

enum ToolboxTab { settings, history }

/// Web-only docked side panel — settings (incl. the signatures/stamps
/// library) and history live here instead of a full-screen navigation, so
/// they stay reachable without leaving the document. Hosts the existing
/// screens unchanged (in `embedded` mode, just without their own AppBar);
/// any sub-flow they push (redraw a signature, the stamp designer, …) still
/// opens as a normal full-screen route on the app's root navigator.
class ToolboxPanel extends StatefulWidget {
  const ToolboxPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<ToolboxPanel> createState() => _ToolboxPanelState();
}

class _ToolboxPanelState extends State<ToolboxPanel> {
  ToolboxTab _tab = ToolboxTab.settings;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Material(
      color: DesignTokens.surfaceHeader,
      elevation: 4,
      child: SizedBox(
        width: 380,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              left: false,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: DesignTokens.hairline1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabSegment(
                          selected: _tab,
                          onSelected: (tab) => setState(() => _tab = tab),
                        ),
                      ),
                      IconButton(
                        tooltip: s['close'],
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab == ToolboxTab.settings ? 0 : 1,
                sizing: StackFit.expand,
                children: [
                  const SettingsScreen(embedded: true),
                  if (HistoryService.isSupported)
                    const HistoryScreen(embedded: true)
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSegment extends StatelessWidget {
  const _TabSegment({required this.selected, required this.onSelected});

  final ToolboxTab selected;
  final ValueChanged<ToolboxTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      children: [
        Expanded(
          child: _TabButton(
            label: s['settings'],
            icon: Icons.settings_outlined,
            selected: selected == ToolboxTab.settings,
            onTap: () => onSelected(ToolboxTab.settings),
          ),
        ),
        if (HistoryService.isSupported) ...[
          const SizedBox(width: 6),
          Expanded(
            child: _TabButton(
              label: s['history'],
              icon: Icons.history,
              selected: selected == ToolboxTab.history,
              onTap: () => onSelected(ToolboxTab.history),
            ),
          ),
        ],
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? DesignTokens.primaryDeep : DesignTokens.textMuted;
    return Material(
      color: selected ? DesignTokens.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
