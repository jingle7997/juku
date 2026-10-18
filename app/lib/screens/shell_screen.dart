import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/chrome.dart';
import 'discover_screen.dart';
import 'following_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  static const _tabs = [
    ('首页', Icons.home_outlined, Icons.home_rounded),
    ('发现', Icons.explore_outlined, Icons.explore_rounded),
    ('追剧', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
    ('我的', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          DiscoverScreen(),
          FollowingScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: GlassBox(
        blur: 26,
        color: palette.glass,
        border: Border(top: BorderSide(color: palette.line)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  NavItem(
                    icon: _tabs[i].$2,
                    activeIcon: _tabs[i].$3,
                    label: _tabs[i].$1,
                    selected: _index == i,
                    onTap: () => setState(() => _index = i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
