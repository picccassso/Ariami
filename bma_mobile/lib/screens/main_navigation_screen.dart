import 'package:flutter/material.dart';
import 'main/library_screen.dart';
import 'main/search_screen.dart';
import 'main/settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // List of screens for each tab
  final List<Widget> _screens = const [
    LibraryScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Main content area
          Expanded(
            child: _screens[_currentIndex],
          ),

          // Mini player placeholder space (60dp reserved for Phase 6)
          // Currently empty, will be implemented in Phase 6
          Container(
            height: 60,
            color: Colors.grey[200],
            child: Center(
              child: Text(
                'Mini Player (Phase 6)',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
