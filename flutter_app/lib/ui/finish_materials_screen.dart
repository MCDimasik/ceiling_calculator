import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/finish_vedomost.dart';
import '../domain/models.dart';
import 'room_navigation.dart';
import 'widgets/screen_scaffold.dart';

/// Finish-only BOM (walls / floor / areas / extra works) — not ceiling guides.
class FinishMaterialsScreen extends StatefulWidget {
  const FinishMaterialsScreen({
    super.key,
    required this.projectId,
    this.roomId,
    this.scope = FinishVedomostScope.all,
  });

  final int projectId;
  final int? roomId;

  /// When not [FinishVedomostScope.all], only that section is shown.
  final FinishVedomostScope scope;

  @override
  State<FinishMaterialsScreen> createState() => _FinishMaterialsScreenState();
}

class _FinishMaterialsScreenState extends State<FinishMaterialsScreen> {
  Project? _project;
  Room? _room;
  List<FinishVedomostLine> _lines = [];
  List<FinishVedomostLine> _ceilingBom = [];
  final Set<String> _expanded = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final label = widget.scope.labelRu;
    if (label != null) {
      _expanded.add(label);
    } else {
      _expanded.add('Потолок');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project =
        await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null && widget.roomId != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;

    List<FinishVedomostLine> lines = [];
    List<FinishVedomostLine> bom = [];
    if (project != null) {
      if (room != null) {
        lines = [
          ...buildFinishVedomostLines(room, project: project),
          ...finishExtraWorkVedomostLines(
            project,
            roomIds: room.id == null ? null : [room.id!],
          ),
        ];
        bom = buildCeilingComponentLines(room, project);
      } else {
        lines = aggregateFinishVedomostLines(project);
        bom = aggregateCeilingComponentLines(project);
      }
    }

    lines = filterFinishVedomostLines(lines, widget.scope);
    if (widget.scope != FinishVedomostScope.all &&
        widget.scope != FinishVedomostScope.ceiling) {
      bom = [];
    }

    setState(() {
      _project = project;
      _room = room;
      _lines = lines;
      _ceilingBom = bom;
      _loading = false;
    });
  }

  Future<void> _share() async {
    final buf = StringBuffer();
    String? lastSection;
    for (final line in _lines) {
      if (line.section != lastSection) {
        if (lastSection != null) buf.writeln();
        buf.writeln('— ${line.section} —');
        lastSection = line.section;
      }
      buf.writeln('${line.name}: ${line.quantity} ${line.unit}'.trim());
    }
    if (_ceilingBom.isNotEmpty) {
      buf.writeln();
      buf.writeln('— Потолок · комплектующие —');
      for (final line in _ceilingBom) {
        buf.writeln('${line.name}: ${line.quantity} ${line.unit}'.trim());
      }
    }
    final text = buf.toString();
    await Clipboard.setData(ClipboardData(text: text));
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Ведомость отделки'),
    );
  }

  Future<void> _openEditor() async {
    final kind = FinishEditorKindX.fromVedomostScope(widget.scope);
    if (kind == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для «Другие работы» откройте сводку объекта'),
        ),
      );
      return;
    }

    // Project-level full vedomost → master plan.
    if (widget.roomId == null && kind == FinishEditorKind.overview) {
      await openFinishEditor(
        context,
        projectId: widget.projectId,
        kind: FinishEditorKind.overview,
      );
      if (mounted) await _load();
      return;
    }

    var roomId = widget.roomId;
    if (roomId == null) {
      final project = _project;
      Room? first;
      if (project != null) {
        for (final r in project.rooms) {
          if (r.hasLayout && r.id != null) {
            first = r;
            break;
          }
        }
      }
      roomId = first?.id;
      if (roomId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет помещений с чертежом')),
        );
        return;
      }
    }

    await openFinishEditor(
      context,
      projectId: widget.projectId,
      roomId: roomId,
      kind: kind,
    );
    if (mounted) await _load();
  }

  Map<String, List<FinishVedomostLine>> _groupBySection() {
    final bySection = <String, List<FinishVedomostLine>>{};
    for (final line in _lines) {
      bySection.putIfAbsent(line.section, () => []).add(line);
    }
    return bySection;
  }

  List<String> _orderedSections(Map<String, List<FinishVedomostLine>> by) {
    const order = ['Пол', 'Потолок', 'Стены', 'Расходники', 'Другие работы'];
    final sections = by.keys.toList();
    sections.sort((a, b) {
      final ai = order.indexOf(a);
      final bi = order.indexOf(b);
      final ao = ai < 0 ? order.length : ai;
      final bo = bi < 0 ? order.length : bi;
      if (ao != bo) return ao.compareTo(bo);
      return a.compareTo(b);
    });
    return sections;
  }

  List<FinishVedomostLine> _detailFor(String section) {
    if (section == 'Потолок') return _ceilingBom;
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scopeLabel = widget.scope.labelRu;
    final titleBase = _room?.name ?? _project?.name ?? 'Отделка';
    final title = scopeLabel == null ? titleBase : '$titleBase · $scopeLabel';
    final theme = Theme.of(context);
    final on = theme.colorScheme.onSurface;
    final bySection = _groupBySection();
    final sections = _orderedSections(bySection);
    final editorKind = FinishEditorKindX.fromVedomostScope(widget.scope);

    final heading = () {
      final roomPart = _room == null
          ? 'Ведомость отделки весь объект'
          : 'Ведомость отделки (${_room!.name})';
      if (scopeLabel == null) return roomPart;
      return '$roomPart · $scopeLabel';
    }();

    return ScreenScaffold(
      backgroundBlur: 0.5,
      dimOpacity: 0.6,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (editorKind != null)
            TextButton(
              onPressed: _openEditor,
              child: const Text('Редактор'),
            ),
          IconButton(
            tooltip: 'Скопировать / поделиться',
            onPressed: _lines.isEmpty && _ceilingBom.isEmpty ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: _lines.isEmpty && _ceilingBom.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  scopeLabel != null
                      ? 'Нет строк по разделу «$scopeLabel».'
                      : (_room == null
                          ? 'Нет данных отделки по объекту. Добавьте чертежи комнат или «Другие работы» в сводке.'
                          : 'Нет данных отделки для помещения. Задайте контур и слои в расчёте отделки.'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: on.withValues(alpha: 0.92),
                    height: 1.35,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  heading,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: on,
                  ),
                ),
                const SizedBox(height: 14),
                for (final section in sections)
                  _ExpandableVedomostSection(
                    section: section,
                    lines: bySection[section]!,
                    detailLines: _detailFor(section),
                    expanded: _expanded.contains(section),
                    onToggle: () {
                      setState(() {
                        if (_expanded.contains(section)) {
                          _expanded.remove(section);
                        } else {
                          _expanded.add(section);
                        }
                      });
                    },
                  ),
              ],
            ),
    );
  }
}

class _ExpandableVedomostSection extends StatelessWidget {
  const _ExpandableVedomostSection({
    required this.section,
    required this.lines,
    required this.detailLines,
    required this.expanded,
    required this.onToggle,
  });

  final String section;
  final List<FinishVedomostLine> lines;
  final List<FinishVedomostLine> detailLines;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onSurface;
    final chip = finishSectionSummaryChip(section, lines);
    final preview = lines.take(expanded ? lines.length : 2).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: on,
                            ),
                          ),
                          if (chip.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              chip,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: on.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: on.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
              if (!expanded) ...[
                Divider(height: 1, color: on.withValues(alpha: 0.08)),
                for (var i = 0; i < preview.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: on.withValues(alpha: 0.06)),
                  _lineRow(theme, on, preview[i], muted: true),
                ],
                const SizedBox(height: 4),
              ] else ...[
                Divider(height: 1, color: on.withValues(alpha: 0.08)),
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: on.withValues(alpha: 0.06)),
                  _lineRow(theme, on, lines[i]),
                ],
                if (detailLines.isNotEmpty) ...[
                  Divider(height: 1, color: on.withValues(alpha: 0.1)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: Text(
                      section == 'Потолок'
                          ? 'Комплектующие каркаса'
                          : 'Подробности',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on,
                      ),
                    ),
                  ),
                  for (var i = 0; i < detailLines.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: on.withValues(alpha: 0.06)),
                    _lineRow(theme, on, detailLines[i]),
                  ],
                ],
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineRow(
    ThemeData theme,
    Color on,
    FinishVedomostLine line, {
    bool muted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              line.name,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: on.withValues(alpha: muted ? 0.75 : 1),
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${line.quantity} ${line.unit}'.trim(),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: on.withValues(alpha: muted ? 0.8 : 1),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
