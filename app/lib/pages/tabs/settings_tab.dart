import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/pages/about/about_page.dart';
import 'package:localsend_app/pages/changelog_page.dart';
import 'package:localsend_app/pages/donation/donation_page.dart';
import 'package:localsend_app/pages/language_page.dart';
import 'package:localsend_app/pages/tabs/settings_tab_controller.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/theme.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/autostart_helper.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/app_rounded_button_style.dart';
import 'package:localsend_app/widget/custom_dropdown_button.dart';
import 'package:localsend_app/widget/dialogs/encryption_disabled_notice.dart';
import 'package:localsend_app/widget/dialogs/quick_save_notice.dart';
import 'package:localsend_app/widget/dialogs/send_panel_color_picker_dialog.dart';
import 'package:localsend_app/widget/dialogs/text_field_tv.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

final _isLinux = checkPlatform([TargetPlatform.linux]);
final _isWindows = checkPlatform([TargetPlatform.windows]);

enum _SettingsPageTab {
  general,
  receiveSend,
  network,
  other,
  advanced,
}

class SettingsTab extends StatefulWidget {
  const SettingsTab();

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  _SettingsPageTab _tab = _SettingsPageTab.general;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: settingsTabControllerProvider,
      builder: (context, vm) {
        final ref = context.ref;
        return ResponsiveListView(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
          children: [
            _SettingsTabBar(
              selected: _tab,
              onSelected: (tab) => setState(() => _tab = tab),
            ),
            const SizedBox(height: 16),
            if (_tab == _SettingsPageTab.general)
              _SettingsSection(
              title: t.settingsTab.general.title,
              children: [
                _SettingsEntry(
                  label: t.settingsTab.general.brightness,
                  child: CustomDropdownButton<ThemeMode>(
                    value: vm.settings.theme,
                    items: vm.themeModes.map((theme) {
                      return DropdownMenuItem(
                        value: theme,
                        alignment: Alignment.center,
                        child: Text(theme.humanName),
                      );
                    }).toList(),
                    onChanged: (theme) => vm.onChangeTheme(context, theme),
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.general.color,
                  child: CustomDropdownButton<ColorMode>(
                    value: vm.settings.colorMode,
                    items: vm.colorModes.map((colorMode) {
                      return DropdownMenuItem(
                        value: colorMode,
                        alignment: Alignment.center,
                        child: Text(colorMode.humanName),
                      );
                    }).toList(),
                    onChanged: vm.onChangeColorMode,
                  ),
                ),
                _ButtonEntry(
                  label: t.settingsTab.general.language,
                  buttonLabel: vm.settings.locale?.humanName ?? t.settingsTab.general.languageOptions.system,
                  onTap: () => vm.onTapLanguage(context),
                ),
                if (checkPlatformIsDesktop()) ...[
                  const _DesktopLayoutSettings(),
                  if (checkPlatformHasTray())
                    _BooleanEntry(
                      label: t.settingsTab.general.minimizeToTray,
                      value: vm.settings.minimizeToTray,
                      onChanged: (b) async {
                        await ref.notifier(settingsProvider).setMinimizeToTray(b);
                      },
                    ),
                  // Linux autostart is simpler, so a boolean entry is used
                  if (_isLinux)
                    _BooleanEntry(
                      label: t.settingsTab.general.launchAtStartup,
                      value: vm.settings.launchAtStartup,
                      onChanged: (b) async {
                        late bool result;
                        if (await isLinuxLaunchAtStartEnabled()) {
                          result = await initDisableAutoStart(vm.settings);
                        } else {
                          result = await initEnableAutoStartAndOpenSettings(vm.settings);
                        }
                        if (result) {
                          await ref.notifier(settingsProvider).setLaunchAtStartup(b);
                        }
                      },
                    ),
                  // Windows requires a manual action, so this settings entry is required
                  if (_isWindows)
                    _SettingsEntry(
                      label: t.settingsTab.general.launchAtStartup,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Theme.of(context).inputDecorationTheme.fillColor,
                          shape: RoundedRectangleBorder(borderRadius: Theme.of(context).inputDecorationTheme.borderRadius),
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: () async {
                          await initDisableAutoStart(vm.settings);
                          await initEnableAutoStartAndOpenSettings(vm.settings, _isWindows);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(t.general.settings, style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ),
                    ),
                  if (_isWindows || _isLinux)
                    Visibility(
                      visible: vm.settings.launchAtStartup || _isWindows,
                      maintainAnimation: true,
                      maintainState: true,
                      child: AnimatedOpacity(
                        opacity: vm.settings.launchAtStartup || _isWindows ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 500),
                        child: _BooleanEntry(
                          label: t.settingsTab.general.launchMinimized,
                          value: vm.settings.autoStartLaunchMinimized,
                          onChanged: (b) async {
                            await initDisableAutoStart(vm.settings);
                            await ref.notifier(settingsProvider).setAutoStartLaunchMinimized(b);
                            await initEnableAutoStartAndOpenSettings(vm.settings, _isWindows);
                          },
                        ),
                      ),
                    ),
                ],
                _BooleanEntry(
                  label: t.settingsTab.general.animations,
                  value: vm.settings.enableAnimations,
                  onChanged: (b) async {
                    await ref.notifier(settingsProvider).setEnableAnimations(b);
                  },
                ),
              ],
            ),
            if (_tab == _SettingsPageTab.receiveSend) ...[
              _SettingsSection(
              title: t.settingsTab.receive.title,
              children: [
                _BooleanEntry(
                  label: t.settingsTab.receive.quickSave,
                  value: vm.settings.quickSave,
                  onChanged: (b) async {
                    final old = vm.settings.quickSave;
                    await ref.notifier(settingsProvider).setQuickSave(b);
                    if (!old && b && context.mounted) {
                      await QuickSaveNotice.open(context);
                    }
                  },
                ),
                _SettingsEntry(
                  label: t.settingsTab.receive.sendLowerPanelOpacity,
                  child: Column(
                    children: [
                      Slider(
                        value: vm.settings.sendLowerPanelOpacity,
                        min: 0.15,
                        max: 0.95,
                        onChanged: (v) async {
                          await ref.notifier(settingsProvider).setSendLowerPanelOpacity(v);
                        },
                      ),
                      Text(
                        '${(vm.settings.sendLowerPanelOpacity * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.receive.sendLowerPanelBrightness,
                  child: Column(
                    children: [
                      Slider(
                        value: vm.settings.sendLowerPanelBrightness,
                        min: 0,
                        max: 0.85,
                        onChanged: (v) async {
                          await ref.notifier(settingsProvider).setSendLowerPanelBrightness(v);
                        },
                      ),
                      Text(
                        '${(vm.settings.sendLowerPanelBrightness * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.receive.sendLowerPanelColor,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).inputDecorationTheme.fillColor,
                      shape: RoundedRectangleBorder(borderRadius: Theme.of(context).inputDecorationTheme.borderRadius),
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () async {
                      final scheme = Theme.of(context).colorScheme;
                      final initial = vm.settings.sendLowerPanelTintArgb == 0
                          ? scheme.surface
                          : Color(vm.settings.sendLowerPanelTintArgb);
                      final picked = await SendPanelColorPickerDialog.open(context, initial);
                      if (picked != null && context.mounted) {
                        await ref.notifier(settingsProvider).setSendLowerPanelTintArgb(picked.value);
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: vm.settings.sendLowerPanelTintArgb == 0
                                ? Theme.of(context).colorScheme.surface
                                : Color(vm.settings.sendLowerPanelTintArgb),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          vm.settings.sendLowerPanelTintArgb == 0
                              ? t.settingsTab.receive.sendLowerPanelColorDefault
                              : '#${vm.settings.sendLowerPanelTintArgb.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                        ),
                      ],
                    ),
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.receive.pasteButtonOpacity,
                  child: Column(
                    children: [
                      Slider(
                        value: vm.settings.pasteButtonOpacity,
                        min: 0.1,
                        max: 0.95,
                        onChanged: (v) async {
                          await ref.notifier(settingsProvider).setPasteButtonOpacity(v);
                        },
                      ),
                      Text(
                        '${(vm.settings.pasteButtonOpacity * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.receive.pasteButtonGradientSpan,
                  child: Column(
                    children: [
                      Slider(
                        value: vm.settings.pasteButtonGradientSpan,
                        min: 0,
                        max: 1,
                        onChanged: (v) async {
                          await ref.notifier(settingsProvider).setPasteButtonGradientSpan(v);
                        },
                      ),
                      Text(
                        '${(vm.settings.pasteButtonGradientSpan * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (checkPlatformWithFileSystem())
                  _SettingsEntry(
                    label: t.settingsTab.receive.destination,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Theme.of(context).inputDecorationTheme.fillColor,
                        shape: RoundedRectangleBorder(borderRadius: Theme.of(context).inputDecorationTheme.borderRadius),
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                      ),
                      onPressed: () async {
                        if (vm.settings.destination != null) {
                          await ref.notifier(settingsProvider).setDestination(null);
                          return;
                        }

                        final directory = await pickDirectoryPath();
                        if (directory != null) {
                          await ref.notifier(settingsProvider).setDestination(directory);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(vm.settings.destination ?? t.settingsTab.receive.downloads, style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                  ),
                if (checkPlatformWithGallery())
                  _BooleanEntry(
                    label: t.settingsTab.receive.saveToGallery,
                    value: vm.settings.saveToGallery,
                    onChanged: (b) async {
                      await ref.notifier(settingsProvider).setSaveToGallery(b);
                    },
                  ),
                _BooleanEntry(
                  label: t.settingsTab.receive.autoFinish,
                  value: vm.settings.autoFinish,
                  onChanged: (b) async {
                    await ref.notifier(settingsProvider).setAutoFinish(b);
                  },
                ),
                _BooleanEntry(
                  label: t.settingsTab.receive.saveToHistory,
                  value: vm.settings.saveToHistory,
                  onChanged: (b) async {
                    await ref.notifier(settingsProvider).setSaveToHistory(b);
                  },
                ),
                _SettingsEntry(
                  label: t.settingsTab.receive.bubbleMaxHeight,
                  child: Column(
                    children: [
                      Slider(
                        value: ref.watch(chatProvider.select((s) => s.bubbleMaxHeight)).clamp(80.0, 480.0).toDouble(),
                        min: 80,
                        max: 480,
                        onChanged: (v) async {
                          await ref.notifier(chatProvider).setBubbleMaxHeight(v);
                        },
                      ),
                      Text(
                        '${ref.watch(chatProvider.select((s) => s.bubbleMaxHeight)).round()} px',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.receive.composerHeight,
                  child: Column(
                    children: [
                      Slider(
                        value: ref.watch(chatProvider.select((s) => s.composerHeight)).clamp(72.0, 320.0).toDouble(),
                        min: 72,
                        max: 320,
                        onChanged: (v) async {
                          await ref.notifier(chatProvider).setComposerHeight(v);
                        },
                      ),
                      Text(
                        '${ref.watch(chatProvider.select((s) => s.composerHeight)).round()} px',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
              _SettingsSection(
                title: t.settingsTab.send.title,
                children: [
                  _BooleanEntry(
                    label: t.settingsTab.send.shareViaLinkAutoAccept,
                    value: vm.settings.shareViaLinkAutoAccept,
                    onChanged: (b) async {
                      await ref.notifier(settingsProvider).setShareViaLinkAutoAccept(b);
                    },
                  ),
                ],
              ),
            ],
            if (_tab == _SettingsPageTab.network)
              _SettingsSection(
              title: t.settingsTab.network.title,
              children: [
                AnimatedCrossFade(
                  crossFadeState: vm.serverState != null &&
                          (vm.serverState!.alias != vm.settings.alias ||
                              vm.serverState!.port != vm.settings.port ||
                              vm.serverState!.https != vm.settings.https)
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topLeft,
                  firstChild: Container(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Text(t.settingsTab.network.needRestart, style: TextStyle(color: Theme.of(context).colorScheme.warning)),
                  ),
                ),
                _SettingsEntry(
                  label: '${t.settingsTab.network.server}${vm.serverState == null ? ' (${t.general.offline})' : ''}',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).inputDecorationTheme.fillColor,
                      borderRadius: Theme.of(context).inputDecorationTheme.borderRadius,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (vm.serverState == null)
                          Tooltip(
                            message: t.general.start,
                            child: TextButton(
                              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                              onPressed: () => vm.onTapStartServer(context),
                              child: const Icon(Icons.play_arrow),
                            ),
                          )
                        else
                          Tooltip(
                            message: t.general.restart,
                            child: TextButton(
                              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                              onPressed: () => vm.onTapRestartServer(context),
                              child: const Icon(Icons.refresh),
                            ),
                          ),
                        Tooltip(
                          message: t.general.stop,
                          child: TextButton(
                            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                            onPressed: vm.serverState == null ? null : vm.onTapStopServer,
                            child: const Icon(Icons.stop),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.network.alias,
                  child: TextFieldTv(
                    name: t.settingsTab.network.alias,
                    controller: vm.aliasController,
                    onChanged: (s) async {
                      await ref.notifier(settingsProvider).setAlias(s);
                    },
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.network.knownDeviceIps,
                  child: TextFieldTv(
                    name: t.settingsTab.network.knownDeviceIps,
                    controller: vm.knownDeviceIpsController,
                    maxLines: 8,
                    onChanged: (s) async {
                      await ref.notifier(settingsProvider).setKnownDeviceIps(s);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Text(
                    t.settingsTab.network.knownDeviceIpsHint,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
            if (_tab == _SettingsPageTab.other)
              _SettingsSection(
              title: t.settingsTab.other.title,
              padding: const EdgeInsets.only(bottom: 0),
              children: [
                _ButtonEntry(
                  label: t.aboutPage.title,
                  buttonLabel: t.general.open,
                  onTap: () async {
                    await context.push(() => const AboutPage());
                  },
                ),
                _ButtonEntry(
                  label: t.settingsTab.other.support,
                  buttonLabel: t.settingsTab.other.donate,
                  onTap: () async {
                    await context.push(() => const DonationPage());
                  },
                ),
                _ButtonEntry(
                  label: t.settingsTab.other.privacyPolicy,
                  buttonLabel: t.general.open,
                  onTap: () async {
                    await launchUrl(
                      Uri.parse('https://localsend.org/#/privacy'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                if (checkPlatform([TargetPlatform.iOS, TargetPlatform.macOS]))
                  _ButtonEntry(
                    label: t.settingsTab.other.termsOfUse,
                    buttonLabel: t.general.open,
                    onTap: () async {
                      await launchUrl(
                        Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
              ],
            ),
            if (_tab == _SettingsPageTab.advanced)
              _SettingsSection(
                title: t.settingsTab.advancedSettings,
                children: [
                  AnimatedCrossFade(
                    crossFadeState: vm.serverState != null &&
                            (vm.serverState!.alias != vm.settings.alias ||
                                vm.serverState!.port != vm.settings.port ||
                                vm.serverState!.https != vm.settings.https)
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topLeft,
                    firstChild: Container(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Text(t.settingsTab.network.needRestart, style: TextStyle(color: Theme.of(context).colorScheme.warning)),
                    ),
                  ),
                  if (checkPlatformIsDesktop() && checkPlatformIsNotWaylandDesktop())
                    _BooleanEntry(
                      label: t.settingsTab.general.saveWindowPlacement,
                      value: vm.settings.saveWindowPlacement,
                      onChanged: (b) async {
                        await ref.notifier(settingsProvider).setSaveWindowPlacement(b);
                      },
                    ),
                  _SettingsEntry(
                    label: t.settingsTab.network.deviceType,
                    child: CustomDropdownButton<DeviceType>(
                      value: vm.deviceInfo.deviceType,
                      items: DeviceType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          alignment: Alignment.center,
                          child: Icon(type.icon),
                        );
                      }).toList(),
                      onChanged: (type) async {
                        await ref.notifier(settingsProvider).setDeviceType(type);
                      },
                    ),
                  ),
                  _SettingsEntry(
                    label: t.settingsTab.network.deviceModel,
                    child: TextFieldTv(
                      name: t.settingsTab.network.deviceModel,
                      controller: vm.deviceModelController,
                      onChanged: (s) async {
                        await ref.notifier(settingsProvider).setDeviceModel(s);
                      },
                    ),
                  ),
                  _SettingsEntry(
                    label: t.settingsTab.network.port,
                    child: TextFieldTv(
                      name: t.settingsTab.network.port,
                      controller: vm.portController,
                      onChanged: (s) async {
                        final port = int.tryParse(s);
                        if (port != null) {
                          await ref.notifier(settingsProvider).setPort(port);
                        }
                      },
                    ),
                  ),
                  _BooleanEntry(
                    label: t.settingsTab.network.encryption,
                    value: vm.settings.https,
                    onChanged: (b) async {
                      final old = vm.settings.https;
                      await ref.notifier(settingsProvider).setHttps(b);
                      if (old && !b && context.mounted) {
                        await EncryptionDisabledNotice.open(context);
                      }
                    },
                  ),
                  _SettingsEntry(
                    label: t.settingsTab.network.multicastGroup,
                    child: TextFieldTv(
                      name: t.settingsTab.network.multicastGroup,
                      controller: vm.multicastController,
                      onChanged: (s) async {
                        await ref.notifier(settingsProvider).setMulticastGroup(s);
                      },
                    ),
                  ),
                  AnimatedCrossFade(
                    crossFadeState: vm.settings.port != defaultPort ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topLeft,
                    firstChild: Container(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Text(
                        t.settingsTab.network.portWarning(defaultPort: defaultPort),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    crossFadeState: vm.settings.multicastGroup != defaultMulticastGroup ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topLeft,
                    firstChild: Container(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Text(
                        t.settingsTab.network.multicastGroupWarning(defaultMulticast: defaultMulticastGroup),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            if (_tab == _SettingsPageTab.other) ...[
            const SizedBox(height: 20),
            const LocalSendLogo(withText: true),
            const SizedBox(height: 5),
            ref.watch(versionProvider).maybeWhen(
                  data: (version) => Text(
                    'Version: $version',
                    textAlign: TextAlign.center,
                  ),
                  orElse: () => Container(),
                ),
            Text(
              '© ${DateTime.now().year} Tien Do Nam',
              textAlign: TextAlign.center,
            ),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () async {
                  await context.push(() => const ChangelogPage());
                },
                icon: const Icon(Icons.history),
                label: Text(t.changelogPage.title),
              ),
            ),
            const SizedBox(height: 80),
            ],
          ],
        );
      },
    );
  }
}

class _SettingsTabBar extends StatelessWidget {
  final _SettingsPageTab selected;
  final ValueChanged<_SettingsPageTab> onSelected;

  const _SettingsTabBar({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = <(_SettingsPageTab, String)>[
      (_SettingsPageTab.general, t.settingsTab.general.title),
      (_SettingsPageTab.receiveSend, t.settingsTab.receiveSend),
      (_SettingsPageTab.network, t.settingsTab.network.title),
      (_SettingsPageTab.other, t.settingsTab.other.title),
      (_SettingsPageTab.advanced, t.settingsTab.advancedSettings),
    ];
    return Row(
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _SettingsTabButton(
              label: tabs[i].$2,
              selected: selected == tabs[i].$1,
              onTap: () => onSelected(tabs[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(kAppRoundedButtonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kAppRoundedButtonRadius),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? scheme.onPrimary : scheme.onSecondaryContainer,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsEntry({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Expanded(
            child: Text(label),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 150,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A specialized version of [_SettingsEntry].
class _BooleanEntry extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BooleanEntry({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SettingsEntry(
      label: label,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              color: theme.inputDecorationTheme.fillColor,
              borderRadius: theme.inputDecorationTheme.borderRadius,
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: theme.colorScheme.primary,
                activeColor: theme.colorScheme.onPrimary,
                inactiveThumbColor: theme.colorScheme.outline,
                inactiveTrackColor: theme.colorScheme.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A specialized version of [_SettingsEntry].
class _ButtonEntry extends StatelessWidget {
  final String label;
  final String buttonLabel;
  final void Function() onTap;

  const _ButtonEntry({
    required this.label,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsEntry(
      label: label,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: Theme.of(context).inputDecorationTheme.fillColor,
          shape: RoundedRectangleBorder(borderRadius: Theme.of(context).inputDecorationTheme.borderRadius),
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            buttonLabel,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final EdgeInsets padding;

  const _SettingsSection({
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.only(bottom: 15),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.only(left: 15, right: 15, top: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopLayoutSettings extends StatefulWidget {
  const _DesktopLayoutSettings();

  @override
  State<_DesktopLayoutSettings> createState() => _DesktopLayoutSettingsState();
}

class _DesktopLayoutSettingsState extends State<_DesktopLayoutSettings> with Refena {
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _historyWidthController;
  late final TextEditingController _navWidthController;
  var _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    final persistence = ref.read(persistenceProvider);
    _widthController = TextEditingController(text: '${persistence.getStartupWindowWidth().round()}');
    _heightController = TextEditingController(text: '${persistence.getStartupWindowHeight().round()}');
    _historyWidthController = TextEditingController(text: '${ref.read(settingsProvider).historyPanelWidth.round()}');
    _navWidthController = TextEditingController(text: '${ref.read(settingsProvider).navigationPanelWidth.round()}');
  }

  @override
  void dispose() {
    if (_initialized) {
      _widthController.dispose();
      _heightController.dispose();
      _historyWidthController.dispose();
      _navWidthController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        _SettingsEntry(
          label: t.settingsTab.general.startupWindowWidth,
          child: TextFieldTv(
            name: t.settingsTab.general.startupWindowWidth,
            controller: _widthController,
            onChanged: (s) async {
              final v = double.tryParse(s.trim());
              if (v != null) {
                await ref.notifier(settingsProvider).setStartupWindowWidth(v);
              }
            },
          ),
        ),
        _SettingsEntry(
          label: t.settingsTab.general.startupWindowHeight,
          child: TextFieldTv(
            name: t.settingsTab.general.startupWindowHeight,
            controller: _heightController,
            onChanged: (s) async {
              final v = double.tryParse(s.trim());
              if (v != null) {
                await ref.notifier(settingsProvider).setStartupWindowHeight(v);
              }
            },
          ),
        ),
        _SettingsEntry(
          label: t.settingsTab.general.navigationPanelWidth,
          child: TextFieldTv(
            name: t.settingsTab.general.navigationPanelWidth,
            controller: _navWidthController,
            onChanged: (s) async {
              final v = double.tryParse(s.trim());
              if (v != null) {
                await ref.notifier(settingsProvider).setNavigationPanelWidth(v);
              }
            },
          ),
        ),
        _BooleanEntry(
          label: t.settingsTab.general.syncSidePanelWidths,
          value: ref.watch(settingsProvider.select((s) => s.syncSidePanelWidths)),
          onChanged: (b) async {
            await ref.notifier(settingsProvider).setSyncSidePanelWidths(b);
            if (b) {
              _navWidthController.text = '${ref.read(settingsProvider).navigationPanelWidth.round()}';
              _historyWidthController.text = '${ref.read(settingsProvider).historyPanelWidth.round()}';
            }
          },
        ),
        _SettingsEntry(
          label: t.settingsTab.general.historyPanelWidth,
          child: TextFieldTv(
            name: t.settingsTab.general.historyPanelWidth,
            controller: _historyWidthController,
            onChanged: (s) async {
              final v = double.tryParse(s.trim());
              if (v != null) {
                await ref.notifier(settingsProvider).setHistoryPanelWidth(v);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: Text(
            t.settingsTab.general.historyPanelWidthHint,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

extension on ThemeMode {
  String get humanName {
    switch (this) {
      case ThemeMode.system:
        return t.settingsTab.general.brightnessOptions.system;
      case ThemeMode.light:
        return t.settingsTab.general.brightnessOptions.light;
      case ThemeMode.dark:
        return t.settingsTab.general.brightnessOptions.dark;
    }
  }
}

extension on ColorMode {
  String get humanName {
    return switch (this) {
      ColorMode.system => t.settingsTab.general.colorOptions.system,
      ColorMode.localsend => t.appName,
      ColorMode.oled => t.settingsTab.general.colorOptions.oled,
      ColorMode.yaru => 'Yaru',
      ColorMode.macos => t.settingsTab.general.colorOptions.macos,
    };
  }
}
