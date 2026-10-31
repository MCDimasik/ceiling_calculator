import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/finish_model.dart';
import '../domain/local_user_role.dart';
import '../domain/project_transfer.dart';
import 'adaptive_layout.dart';
import 'desktop_cascade.dart';
import 'documentation_flow_screens.dart';
import 'director_archive_screen.dart';
import 'materials_flow_screens.dart';
import 'pricing_hub_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'sync_inbox_screen.dart';
import 'widgets/app_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    /// Inside [DesktopShell] rail — skip duplicate full-page chrome cues.
    this.embeddedInDesktopShell = false,
  });

  final bool embeddedInDesktopShell;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _otaPromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSilentOta());
  }

  Future<void> _runSilentOta() async {
    if (!mounted) return;
    final u = AppScope.of(context).appUpdate;
    final result = await u.runSilentCycle();
    if (!mounted || _otaPromptShown) return;
    if (!result.shouldPromptInstall) return;
    _otaPromptShown = true;
    final ver = result.message ?? u.pendingVersionName ?? '';
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Обновление готово'),
        content: Text(
          ver.isEmpty
              ? 'Скачана новая версия. Установить сейчас?\n'
                  'Данные на устройстве сохранятся.'
              : 'Скачана версия $ver. Установить сейчас?\n'
                  'Данные на устройстве сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Установить'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      await u.openPendingInstaller();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть установщик: $e')),
      );
    }
  }

  void _openOrCascade(
    BuildContext context, {
    required DesktopCascadeModule cascadeModule,
    required WidgetBuilder phoneBuilder,
  }) {
    final cascade = DesktopCascadeHost.maybeOf(context);
    if (cascade != null) {
      cascade.openModule(cascadeModule);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: phoneBuilder));
  }

  List<Widget> _navTiles(BuildContext context) {
    final role = AppScope.of(context).user.effectiveRole;
    final sync = AppScope.of(context).sync;
    final inboxBadge = sync.pendingTotal;
    final desktop = AdaptiveBreakpoints.useDesktopChrome(context);
    final large = widget.embeddedInDesktopShell;
    return [
      if (role.canCeilingLayout)
        _HomeNavTile(
          icon: Icons.grid_on_outlined,
          label: 'Раскладка потолка',
          subtitle: 'Сетка, направляющие, светильники',
          dense: desktop && !large,
          large: large,
          onTap: () => _openOrCascade(
            context,
            cascadeModule: DesktopCascadeModule.ceiling,
            phoneBuilder: (_) => const ProjectsScreen(
              module: AppModule.ceilingLayout,
            ),
          ),
        ),
      if (role.canCeilingMaterials)
        _HomeNavTile(
          icon: Icons.inventory_2_outlined,
          label: 'Материалы потолка',
          subtitle: 'BOM по этажу / объекту / комнате',
          dense: desktop && !large,
          large: large,
          onTap: () => _openOrCascade(
            context,
            cascadeModule: DesktopCascadeModule.materialsCeiling,
            phoneBuilder: (_) => const ProjectsScreen(
              materialsCalcMode: MaterialsCalcMode.ceiling,
            ),
          ),
        ),
      if (role.canFinish)
        _HomeNavTile(
          icon: Icons.apartment_outlined,
          label: 'Отделка',
          subtitle: 'Пол, стены, потолок, обзор',
          dense: desktop && !large,
          large: large,
          onTap: () => _openOrCascade(
            context,
            cascadeModule: DesktopCascadeModule.finish,
            phoneBuilder: (_) =>
                const ProjectsScreen(module: AppModule.finish),
          ),
        ),
      if (role.canDocumentation)
        _HomeNavTile(
          icon: Icons.description_outlined,
          label: 'Документация',
          subtitle: 'КП, КС, ведомости, акты',
          dense: desktop && !large,
          large: large,
          onTap: () => _openOrCascade(
            context,
            cascadeModule: DesktopCascadeModule.documentation,
            phoneBuilder: (_) => const DocumentationProjectsScreen(),
          ),
        ),
      if (role.canCeilingImport)
        _HomeNavTile(
          icon: Icons.file_upload_outlined,
          label: 'Импорт проекта',
          subtitle: 'Файл объекта с другого устройства',
          dense: desktop,
          onTap: () async {
            try {
              final p = await importProjectFile(
                AppScope.of(context).projects,
              );
              if (!mounted) return;
              if (p == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    p.rooms.isEmpty
                        ? 'Импортирован «${p.name}»'
                        : 'Импортирован «${p.name}» · комнат: ${p.rooms.length}',
                  ),
                ),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка: $e')),
              );
            }
          },
        ),
      if (role.canPricing)
        _HomeNavTile(
          icon: Icons.payments_outlined,
          label: 'Расценки',
          subtitle: 'Каталог работ, поставщики, комплекты',
          dense: desktop && !large,
          large: large,
          onTap: () => _openOrCascade(
            context,
            cascadeModule: DesktopCascadeModule.pricing,
            phoneBuilder: (_) => const PricingHubScreen(),
          ),
        ),
      if (role.canArchive)
        _HomeNavTile(
          icon: Icons.archive_outlined,
          label: 'Архив',
          subtitle: 'Документы · PDF / Word / Excel',
          dense: desktop && !large,
          large: large,
          onTap: () => _openOrCascade(
            context,
            cascadeModule: DesktopCascadeModule.archive,
            phoneBuilder: (_) => const DirectorArchiveScreen(),
          ),
        ),
      _HomeNavTile(
        icon: Icons.inbox_outlined,
        label: 'Входящие',
        subtitle: sync.isSignedIn
            ? (inboxBadge > 0
                ? 'Новых: $inboxBadge'
                : 'Сообщения: проекты, расценки, комплекты')
            : 'Мессенджер синка · войдите свитчером теста',
        badgeCount: inboxBadge,
        dense: desktop && !large,
        large: large,
        onTap: () => _openOrCascade(
          context,
          cascadeModule: DesktopCascadeModule.inbox,
          phoneBuilder: (_) => const SyncInboxScreen(),
        ),
      ),
      if (role.canSettings)
        _HomeNavTile(
          icon: Icons.settings_outlined,
          label: 'Настройки',
          subtitle: role.canOfflineDeviceSync
              ? 'Профиль, облако, офлайн-синк'
              : 'Профиль, роли, тема',
          dense: desktop && !large,
          large: large,
          onTap: () => _openOrCascade(
            context,
            cascadeModule: DesktopCascadeModule.settings,
            phoneBuilder: (_) => const SettingsScreen(),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final role = AppScope.of(context).user.effectiveRole;
    final profile = AppScope.of(context).user.profile;
    final pending = AppScope.of(context).user.isPending;
    final desktop = AdaptiveBreakpoints.useDesktopChrome(context);
    final embedded = widget.embeddedInDesktopShell;
    final tiles = _navTiles(context);

    final light = Theme.of(context).brightness == Brightness.light;
    final titleColor = light
        ? Theme.of(context).colorScheme.onSurface
        : Colors.white;
    final subtitleColor = light
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Colors.white70;
    final header = Column(
      children: [
        Center(
          child: Builder(
            builder: (context) {
              final logo = Image.asset(
                'assets/media/logo-visota.PNG',
                height: embedded ? 96 : (desktop ? 72 : 88),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              );
              // Dark: force white logo on photo. Light: natural brand colors.
              if (light) return logo;
              return ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0, 0, 0, 0, 255,
                  0, 0, 0, 0, 255,
                  0, 0, 0, 0, 255,
                  0, 0, 0, 1, 0,
                ]),
                child: logo,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Высота Калькулятор',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: titleColor,
                fontSize: embedded ? 34 : null,
                shadows: light
                    ? null
                    : const [
                        Shadow(blurRadius: 8, color: Colors.black54),
                      ],
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          profile == null
              ? 'Гость · ${role.labelRu}'
              : (pending
                  ? '${profile.fullName} · ожидает · ${role.labelRu}'
                  : '${profile.fullName} · ${role.labelRu} · @${profile.login}'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: subtitleColor,
                fontSize: embedded ? 16 : null,
              ),
        ),
        SizedBox(height: embedded ? 32 : (desktop ? 28 : 20)),
      ],
    );

    final body = desktop
        ? LayoutBuilder(
            builder: (context, constraints) {
              // FHD: 3 columns fill the screen; laptop: 2.
              final wide = constraints.maxWidth >= 1400;
              final maxW = embedded
                  ? (wide ? 1240.0 : 960.0)
                  : (wide ? 1100.0 : 960.0);
              final tileExtent = embedded
                  ? (wide ? 128.0 : 118.0)
                  : 88.0;
              final gap = embedded ? 18.0 : 12.0;
              final cols = constraints.maxWidth >= 1400
                  ? 3
                  : (constraints.maxWidth >= 720 ? 2 : 1);
              final gridW = (maxW < constraints.maxWidth
                      ? maxW
                      : constraints.maxWidth)
                  .clamp(280.0, maxW);
              final crossExtent = (gridW - gap * (cols - 1)) / cols;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: gridW),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: embedded ? 28 : 24),
                      ),
                      SliverToBoxAdapter(child: header),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          embedded ? 4 : 0,
                          0,
                          embedded ? 4 : 0,
                          embedded ? 56 : 48,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: gap,
                            crossAxisSpacing: gap,
                            mainAxisExtent: tileExtent,
                            childAspectRatio: crossExtent / tileExtent,
                          ),
                          delegate: SliverChildListDelegate(tiles),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            children: [header, ...tiles],
          );

    if (embedded) {
      return Material(type: MaterialType.transparency, child: body);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        dim: true,
        allowVideo: !desktop,
        child: SafeArea(child: body),
      ),
    );
  }
}

/// Same quiet Card language as projects / rooms lists.
/// Custom row (not ListTile) so content stays vertically centered in tall grid cells.
class _HomeNavTile extends StatelessWidget {
  const _HomeNavTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
    this.dense = false,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final int badgeCount;
  final bool dense;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = large
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: scheme.onSurface,
            )
        : Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            );
    final subtitleStyle = large
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              color: scheme.onSurfaceVariant,
            )
        : Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            );

    return Padding(
      padding: EdgeInsets.only(bottom: dense || large ? 0 : 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: large ? 18 : 16,
              vertical: large ? 14 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: large ? 28 : 20,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: Icon(icon, size: large ? 28 : 24),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: large ? 16 : 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: large ? 4 : 2),
                      Text(
                        subtitle,
                        style: subtitleStyle,
                        maxLines: large ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
