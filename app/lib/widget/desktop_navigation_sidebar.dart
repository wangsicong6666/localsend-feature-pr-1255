import 'package:collection/collection.dart';
import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/rail_rounded_tile.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:localsend_app/theme.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Left sidebar: tab buttons + nearby devices (desktop/tablet).
class DesktopNavigationSidebar extends StatelessWidget {
  final bool extended;
  final HomeTab currentTab;
  final ValueChanged<int> onTabSelected;

  const DesktopNavigationSidebar({
    required this.extended,
    required this.currentTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.ref.watch(sendTabVmProvider);
    final devices = vm.nearbyDevices.toList();
    final chat = context.ref.watch(chatProvider);
    final active = chat.activeFingerprint;
    final (scanningFavorites, scanningIps) =
        context.ref.watch(nearbyDevicesProvider.select((s) => (s.runningFavoriteScan, s.runningIps)));
    final animations = context.ref.watch(animationProvider);
    final spinning = (scanningFavorites || scanningIps.isNotEmpty) && animations;
    final pasteOpacity = context.ref.watch(settingsProvider.select((s) => s.pasteButtonOpacity));
    final pasteGradient = context.ref.watch(settingsProvider.select((s) => s.pasteButtonGradientSpan));

    return Material(
      color: Theme.of(context).cardColorWithElevation,
      child: Column(
        children: [
          if (extended) ...[
            const SizedBox(height: 20),
            const Text(
              'LocalSend',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 12),
          ...HomeTab.values.map((tab) {
            return RailRoundedTile(
              selected: currentTab == tab,
              extended: extended,
              icon: tab.icon,
              label: extended ? tab.label : null,
              pasteSelectionStyle: true,
              pasteOpacity: pasteOpacity,
              pasteGradientSpan: pasteGradient,
              onTap: () => onTabSelected(tab.index),
            );
          }),
          if (currentTab == HomeTab.transfer) ...[
            const SizedBox(height: kRailTileOuterVerticalPadding),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  if (extended)
                    Expanded(
                      child: Text(
                        t.sendTab.nearbyDevices,
                        style: Theme.of(context).textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  RotatingWidget(
                    duration: const Duration(seconds: 2),
                    spinning: spinning,
                    reverse: true,
                    child: CustomIconButton(
                      onPressed: () async {
                        context.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
                        await context.ref.dispatchAsync(StartSmartScan(forceLegacy: true));
                      },
                      child: const Icon(Icons.sync, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: devices.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        t.general.offline,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final favoriteEntry = vm.favoriteDevices.firstWhereOrNull((e) => e.fingerprint == device.fingerprint);
                        final name = favoriteEntry?.alias ?? device.alias;
                        final key = chatPeerKey(device.fingerprint, device.ip);
                        return RailRoundedTile(
                          selected: key == active,
                          extended: extended,
                          icon: device.deviceType.icon,
                          label: extended ? name : null,
                          subtitle: extended ? device.ip : null,
                          tooltip: extended ? null : '$name\n${device.ip}',
                          onTap: () async {
                            await context.ref.notifier(chatProvider).openConversation(
                                  fingerprint: device.fingerprint,
                                  alias: name,
                                  ip: device.ip,
                                  port: device.port,
                                  https: device.https,
                                );
                          },
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  extended ? t.chat.recent : '',
                  style: Theme.of(context).textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: chat.conversations.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: chat.conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = chat.conversations[index];
                        final online = devices.firstWhereOrNull((device) => chatPeerKey(device.fingerprint, device.ip) == conversation.fingerprint);
                        return RailRoundedTile(
                          selected: conversation.fingerprint == active,
                          extended: extended,
                          icon: Icons.forum_outlined,
                          label: extended ? conversation.alias : null,
                          subtitle: extended ? (online == null ? t.chat.offline : t.chat.online) : null,
                          tooltip: extended ? null : conversation.alias,
                          onTap: () async {
                            await context.ref.notifier(chatProvider).openConversation(
                                  fingerprint: online?.fingerprint ?? conversation.fingerprint,
                                  alias: online?.alias ?? conversation.alias,
                                  ip: online?.ip ?? conversation.lastIp ?? '',
                                  port: online?.port ?? conversation.lastPort ?? defaultPort,
                                  https: online?.https ?? conversation.https ?? true,
                                );
                          },
                        );
                      },
                    ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}
