import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/widget/chat/chat_panel.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class TransferTab extends StatelessWidget {
  const TransferTab();

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: sendTabVmProvider,
      init: (context, ref) {
        ref.dispatchAsync(SendTabInitAction(context));
      },
      builder: (context, _) {
        final vm = context.ref.watch(receiveTabVmProvider);
        final ref = context.ref;
        final isDesktop = MediaQuery.sizeOf(context).width >= 800;
        final historyPanelVisible = ref.watch(settingsProvider.select((s) => s.historyPanelVisible));

        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isDesktop && !historyPanelVisible)
                        Tooltip(
                          message: t.receiveTab.showHistoryPanel,
                          child: CustomIconButton(
                            onPressed: () async {
                              await ref.notifier(settingsProvider).setHistoryPanelVisible(true);
                            },
                            child: const Icon(Icons.view_sidebar),
                          ),
                        ),
                      if (!isDesktop || !historyPanelVisible)
                        CustomIconButton(
                          onPressed: () async {
                            await context.push(() => const ReceiveHistoryPage());
                          },
                          child: const Icon(Icons.history),
                        ),
                      CustomIconButton(
                        onPressed: vm.toggleAdvanced,
                        child: const Icon(Icons.info),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: ChatPanel()),
              ],
            ),
            if (vm.showAdvanced)
              Positioned(
                top: 48,
                right: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${t.receiveTab.infoBox.alias}: ${vm.serverState?.alias ?? '-'}'),
                        Text('${t.receiveTab.infoBox.port}: ${vm.serverState?.port ?? '-'}'),
                        ...vm.localIps.map((ip) => Text('${t.receiveTab.infoBox.ip}: $ip')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
