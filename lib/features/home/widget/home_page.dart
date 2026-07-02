import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/daily_subscription_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    // final hasAnyProfile = ref.watch(hasAnyProfileProvider);
    final activeProfile = ref.watch(activeProfileProvider);

    return Scaffold(
      appBar: AppBar(
        // leading: (RootScaffold.stateKey.currentState?.hasDrawer ?? false) && showDrawerButton(context)
        //     ? DrawerButton(
        //         onPressed: () {
        //           RootScaffold.stateKey.currentState?.openDrawer();
        //         },
        //       )
        //     : null,
        title: Row(
          children: [
            Assets.images.logo.svg(height: 24),
            const Gap(8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: t.common.appTitle),
                  const TextSpan(text: " "),
                  const WidgetSpan(child: AppVersionLabel(), alignment: PlaceholderAlignment.middle),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // IconButton(
          //     onPressed: () => const QuickSettingsRoute().push(context),
          //     icon: const Icon(FluentIcons.options_24_filled),
          //     material: (context, platform) => MaterialIconButtonData(
          //           tooltip: t.config.quickSettings,
          //         )),
          // IconButton(
          //     onPressed: () => const AddProfileRoute().push(context),
          //     icon: const Icon(FluentIcons.add_circle_24_filled),
          //     material: (context, platform) => MaterialIconButtonData(
          //           tooltip: t.profile.add.buttonText,
          //         )),
          _DailySubButton(),
          Semantics(
            key: const ValueKey("profile_add_button"),
            label: t.pages.profiles.add,
            child: IconButton(
              icon: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
              onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            ),
          ),
          const Gap(8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'), // Replace with your image path
            fit: BoxFit.cover,
            opacity: 0.09,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(Colors.white.withValues(alpha: .15), BlendMode.srcIn) //
                : ColorFilter.mode(
                    Colors.grey.withValues(alpha: 1),
                    BlendMode.srcATop,
                  ), // Apply white tint in dark mode
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 600, // Set the maximum width here
                ),
                child: CustomScrollView(
                  slivers: [
                    // switch (activeProfile) {
                    // AsyncData(value: final profile?) =>
                    MultiSliver(
                      children: [
                        // const Gap(100),
                        switch (activeProfile) {
                          AsyncData(value: final profile?) => ProfileTile(
                            profile: profile,
                            isMain: true,
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          _ => const Text(""),
                        },
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [ConnectionButton(), ActiveProxyDelayIndicator()],
                                ),
                              ),
                              ActiveProxyFooter(),
                              Gap(32),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // AsyncData() => switch (hasAnyProfile) {
                    //     AsyncData(value: true) => const EmptyActiveProfileHomeBody(),
                    //     _ => const EmptyProfilesHomeBody(),
                    //   },
                    // AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                    // _ => const SliverToBoxAdapter(),
                    // },
                  ],
                ),
              ),
            ),
            if (ref.watch(hasAnyProfileProvider).value ?? false)
              Positioned(
                right: 0,
                left: 0,
                bottom: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Material(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        onTap: () => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings(),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.pages.home.quickSettings),
                              const Gap(4),
                              const Icon(Icons.arrow_drop_up_rounded, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DailySubButton extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(dailySubscriptionNotifierProvider);
    final isLoading = state is DailySubLoading;

    ref.listen(dailySubscriptionNotifierProvider, (_, next) {
      if (next is DailySubDone) {
        final messenger = ScaffoldMessenger.of(context);
        if (next.added == 0 && next.skipped > 0 && next.failed == 0 && next.deleted == 0) {
          messenger.showSnackBar(
            const SnackBar(content: Text('今日订阅已是最新'), duration: Duration(seconds: 2)),
          );
        } else {
          final msg = StringBuffer();
          if (next.added > 0) msg.write('已添加 ${next.added} 个');
          if (next.skipped > 0) msg.write('  跳过 ${next.skipped} 个');
          if (next.deleted > 0) msg.write('  清理旧订阅 ${next.deleted} 个');
          if (next.failed > 0) msg.write('  失败 ${next.failed} 个');
          messenger.showSnackBar(
            SnackBar(content: Text(msg.toString().trim()), duration: const Duration(seconds: 3)),
          );
        }
      }
    });

    return IconButton(
      tooltip: '添加今日订阅',
      icon: isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
            )
          : Icon(Icons.cloud_download_rounded, color: theme.colorScheme.primary),
      onPressed: isLoading ? null : () => _showModeDialog(context, ref),
    );
  }

  void _showModeDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('更新当日订阅'),
          content: const Text('请选择订阅类型：'),
          actionsAlignment: MainAxisAlignment.start,
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('v2ray 订阅'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ref.read(dailySubscriptionNotifierProvider.notifier).addTodaySubscriptions(DailySubMode.txt);
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.code_rounded),
                  label: const Text('sing-box 订阅'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ref.read(dailySubscriptionNotifierProvider.notifier).addTodaySubscriptions(DailySubMode.json);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
