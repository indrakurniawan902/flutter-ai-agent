import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Item definition for [FloatingBottomNavBar].
class NavigationBarItemData {
  final String keyName;
  final String label;
  final IconData icon;
  final String indicatorKey;

  const NavigationBarItemData({
    required this.keyName,
    required this.label,
    required this.icon,
    required this.indicatorKey,
  });
}

/// Floating glassmorphism bottom navigation bar for Flames.
///
/// Features:
/// - Dark translucent obsidian background with subtle blur (`ImageFilter.blur`).
/// - Thin technical border with subtle elevation.
/// - Active electric teal glow indicator with smooth transitions.
/// - Haptic feedback on tab switch.
/// - Zero emojis in chrome.
class FloatingBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<NavigationBarItemData> items = [
    NavigationBarItemData(
      keyName: 'nav_item_chat',
      label: 'Chat',
      icon: Icons.terminal_outlined,
      indicatorKey: 'nav_indicator_chat',
    ),
    NavigationBarItemData(
      keyName: 'nav_item_skills',
      label: 'Skills',
      icon: Icons.extension_outlined,
      indicatorKey: 'nav_indicator_skills',
    ),
    NavigationBarItemData(
      keyName: 'nav_item_node',
      label: 'Node',
      icon: Icons.router_outlined,
      indicatorKey: 'nav_indicator_node',
    ),
    NavigationBarItemData(
      keyName: 'nav_item_vault',
      label: 'Vault',
      icon: Icons.storage_outlined,
      indicatorKey: 'nav_indicator_vault',
    ),
    NavigationBarItemData(
      keyName: 'nav_item_settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      indicatorKey: 'nav_indicator_settings',
    ),
  ];

  const FloatingBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  void _handleTap(int index) {
    HapticFeedback.selectionClick();
    onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Container(
          key: const Key('floating_bottom_nav_bar'),
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: HermesColors.cardSurface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: HermesColors.border.withValues(alpha: 0.8),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final isActive = index == currentIndex;

                  return _NavItemWidget(
                    item: item,
                    isActive: isActive,
                    onTap: () => _handleTap(index),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _NavItemWidget extends StatelessWidget {
  final NavigationBarItemData item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItemWidget({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = HermesColors.electricTeal;
    final inactiveColor = HermesColors.inkSecondary;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key(item.keyName),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: 22,
                  color: isActive ? activeColor : inactiveColor,
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermesTypography.monospace(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? activeColor : inactiveColor,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                if (isActive)
                  Container(
                    key: Key(item.indicatorKey),
                    width: 14,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.7),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 2.5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
