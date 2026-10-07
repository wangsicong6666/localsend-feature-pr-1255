import 'dart:io';

import 'package:common/common.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/init.dart';
import 'package:localsend_app/pages/tabs/transfer_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/ui/home_tab_provider.dart';
import 'package:localsend_app/theme.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/panels/navigation_sidebar_panel.dart';
import 'package:localsend_app/widget/panels/receive_history_panel.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum HomeTab {
  transfer(Icons.swap_vert),
  settings(Icons.settings);

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.transfer:
        return t.transferTab.title;
      case HomeTab.settings:
        return t.settingsTab.title;
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  late PageController _pageController;
  HomeTab _currentTab = HomeTab.transfer;

  bool _dragAndDropIndicator = false;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: widget.initialTab.index);
    _currentTab = widget.initialTab;

    ensureRef((ref) async {
      ref.redux(homeTabProvider).dispatch(SetHomeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart, _goToPage);
      if (widget.appStart && checkPlatformIsDesktop()) {
        await ref.dispatchAsync(StartSmartScan(forceLegacy: false));
      }
      try {
        await ref.notifier(chatProvider).ensureReady();
      } catch (e, st) {
        logChatError(e, st);
      }
    });
  }

  void _goToPage(int index) {
    final tab = HomeTab.values[index];
    ref.redux(homeTabProvider).dispatch(SetHomeTabAction(tab));
    setState(() {
      _currentTab = tab;
      _pageController.jumpToPage(_currentTab.index);
    });
  }

  void _syncTabFromProvider(HomeTab providerTab) {
    if (providerTab == _currentTab) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final latest = ref.read(homeTabProvider);
      if (latest != _currentTab) {
        setState(() => _currentTab = latest);
        _pageController.jumpToPage(latest.index);
      }
    });
  }

  void _switchToReceiveIfIncoming(SessionStatus? status) {
    if (status != SessionStatus.waiting || _currentTab == HomeTab.transfer) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (ref.read(serverProvider)?.session?.status == SessionStatus.waiting && _currentTab != HomeTab.transfer) {
        _goToPage(HomeTab.transfer.index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change

    final providerTab = ref.watch(homeTabProvider);
    final sessionStatus = ref.watch(serverProvider.select((s) => s?.session?.status));
    _syncTabFromProvider(providerTab);
    _switchToReceiveIfIncoming(sessionStatus);

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        if (!mounted) {
          return;
        }
        final paths = <String>[];
        var skippedDirs = 0;
        for (final file in event.files) {
          if (Directory(file.path).existsSync()) {
            skippedDirs++;
          } else {
            paths.add(file.path);
          }
        }
        if (skippedDirs > 0) {
          context.showSnackBar(t.chat.folderRejected);
        }
        if (paths.isEmpty) {
          return;
        }
        if (ref.read(chatProvider).activeFingerprint == null) {
          context.showSnackBar(t.chat.selectDeviceFirst);
          return;
        }
        await ref.notifier(chatProvider).addPaths(paths);
      },
      child: ResponsiveBuilder(
        builder: (sizingInformation) {
          final showHistoryPanel = sizingInformation.isDesktop && ref.watch(settingsProvider.select((s) => s.historyPanelVisible));
          return Scaffold(
            body: Row(
              children: [
                if (!sizingInformation.isMobile)
                  NavigationSidebarPanel(
                    currentTab: _currentTab,
                    onTabSelected: _goToPage,
                  ),
                Expanded(
                  child: SafeArea(
                    left: sizingInformation.isMobile,
                    child: Stack(
                      children: [
                        PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: const [
                            TransferTab(),
                            SettingsTab(),
                          ],
                        ),
                        if (_dragAndDropIndicator)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.file_download, size: 128),
                                const SizedBox(height: 30),
                                Text(t.chat.dropHint, style: Theme.of(context).textTheme.titleLarge),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (showHistoryPanel) const ReceiveHistoryPanel(),
              ],
            ),
            bottomNavigationBar: sizingInformation.isMobile
                ? NavigationBar(
                    selectedIndex: _currentTab.index,
                    onDestinationSelected: _goToPage,
                    destinations: HomeTab.values.map((tab) {
                      return NavigationDestination(icon: Icon(tab.icon), label: tab.label);
                    }).toList(),
                  )
                : null,
          );
        },
      ),
    );
  }
}
