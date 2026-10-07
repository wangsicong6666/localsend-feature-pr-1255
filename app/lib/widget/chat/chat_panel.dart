import 'package:collection/collection.dart';
import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/widget/chat/chat_composer.dart';
import 'package:localsend_app/widget/chat/chat_message_list.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:refena_flutter/refena_flutter.dart';

class ChatPanel extends StatelessWidget {
  const ChatPanel();

  @override
  Widget build(BuildContext context) {
    final chat = context.ref.watch(chatProvider);
    final sendVm = context.ref.watch(sendTabVmProvider);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final active = chat.activeFingerprint;
    final online = active == null
        ? null
        : sendVm.nearbyDevices.firstWhereOrNull((device) => chatPeerKey(device.fingerprint, device.ip) == active);
    final conversation = active == null ? null : chat.conversations.firstWhereOrNull((item) => item.fingerprint == active);
    final title = online?.alias ?? conversation?.alias;

    return Column(
      children: [
        if (active != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title ?? active,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  online == null ? t.chat.offline : t.chat.online,
                  style: TextStyle(color: online == null ? Theme.of(context).colorScheme.outline : const Color(0xFF3DDC97), fontSize: 12),
                ),
              ],
            ),
          ),
        if (narrow) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(t.sendTab.nearbyDevices, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          SizedBox(
            height: 132,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final device in sendVm.nearbyDevices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: DeviceListTile(
                      device: device,
                      isFavorite: sendVm.favoriteDevices.any((e) => e.fingerprint == device.fingerprint),
                      nameOverride: sendVm.favoriteDevices.firstWhereOrNull((e) => e.fingerprint == device.fingerprint)?.alias,
                      onFavoriteTap: () async => sendVm.onToggleFavorite(device),
                      onTap: () async {
                        final fav = sendVm.favoriteDevices.firstWhereOrNull((e) => e.fingerprint == device.fingerprint);
                        await context.ref.notifier(chatProvider).openConversation(
                              fingerprint: device.fingerprint,
                              alias: fav?.alias ?? device.alias,
                              ip: device.ip,
                              port: device.port,
                              https: device.https,
                            );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
        Expanded(
          child: ChatMessageList(
            activeFingerprint: active,
            messages: chat.messages,
            bubbleMaxHeight: chat.bubbleMaxHeight,
          ),
        ),
        const Divider(height: 1),
        ChatComposer(
          onlineDevice: online,
          enabled: active != null,
        ),
      ],
    );
  }
}
