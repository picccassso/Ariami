import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'player/screens/player_root.dart';
import 'player/services/debug_overlay_service.dart';
import 'player/services/player_host.dart';
import 'player/services/quick_jump_service.dart';
import 'player/services/search_settings_service.dart';
import 'player/services/sensitive_info_service.dart';
import 'player/theme/player_theme.dart';
import 'web_host/web_player_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SensitiveInfoService.instance.load();
  await DebugOverlayService.instance.load();
  final searchSettingsService = SearchSettingsService();
  await searchSettingsService.initialize();
  final quickJumpService = QuickJumpService();
  await quickJumpService.initialize();

  runApp(
    AriamiWebApp(
      searchSettingsService: searchSettingsService,
      quickJumpService: quickJumpService,
      host: createWebPlayerHost(),
    ),
  );
}

class AriamiWebApp extends StatelessWidget {
  const AriamiWebApp({
    super.key,
    required this.searchSettingsService,
    required this.quickJumpService,
    required this.host,
  });

  final SearchSettingsService searchSettingsService;
  final QuickJumpService quickJumpService;
  final PlayerHost host;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SearchSettingsService>.value(
          value: searchSettingsService,
        ),
        ChangeNotifierProvider<QuickJumpService>.value(
          value: quickJumpService,
        ),
      ],
      child: MaterialApp(
        title: 'Ariami',
        debugShowCheckedModeBanner: false,
        theme: PlayerTheme.setup(),
        home: PlayerRoot(host: host),
      ),
    );
  }
}
