import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/models.dart';
import '../domain/opening_templates.dart';
import '../domain/special_space.dart';
import 'finish_room_screen.dart';
import 'widgets/numeric_input.dart';
import 'widgets/screen_scaffold.dart';
import 'widgets/stair_schematic_painters.dart';

/// Editor for volume-only rooms and parametric stairwells (no floor plan).
class SpecialSpaceScreen extends StatefulWidget {
  const SpecialSpaceScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<SpecialSpaceScreen> createState() => _SpecialSpaceScreenState();
}

class _SpecialSpaceScreenState extends State<SpecialSpaceScreen> {
  Room? _room;
  Project? _project;
  bool _loading = true;
  String? _error;

  late SpecialSpace _space;
  late StairwellParams _stair;
  int? _selectedOpeningIndex;

  final _nameCtrl = TextEditingController();
  final _wallsCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _ceilingCtrl = TextEditingController();

  final _storeyHCtrl = TextEditingController();
  final _totalHCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _depthCtrl = TextEditingController();
  final _doorsCtrl = TextEditingController();
  final _knownWallsCtrl = TextEditingController();
  final _floorsFromCtrl = TextEditingController();
  final _floorsToCtrl = TextEditingController();
  /// Created in [_ensureLandingCtrls] so hot-reload of this screen stays safe.
  TextEditingController? _midLandingCtrl;
  TextEditingController? _botLandingCtrl;

  bool _started = false;

  void _ensureLandingCtrls() {
    _midLandingCtrl ??= TextEditingController();
    _botLandingCtrl ??= TextEditingController();
  }

  TextEditingController get midLandingCtrl {
    _ensureLandingCtrls();
    return _midLandingCtrl!;
  }

  TextEditingController get botLandingCtrl {
    _ensureLandingCtrls();
    return _botLandingCtrl!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLandingCtrls();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _wallsCtrl,
      _floorCtrl,
      _ceilingCtrl,
      _storeyHCtrl,
      _totalHCtrl,
      _widthCtrl,
      _depthCtrl,
      _doorsCtrl,
      _knownWallsCtrl,
      _floorsFromCtrl,
      _floorsToCtrl,
      _midLandingCtrl,
      _botLandingCtrl,
    ]) {
      c?.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final project =
          await AppScope.of(context).projects.getProject(widget.projectId);
      Room? room;
      if (project != null) {
        for (final r in project.rooms) {
          if (r.id == widget.roomId) room = r;
        }
      }
      if (room == null) {
        setState(() {
          _error = 'Помещение не найдено';
          _loading = false;
        });
        return;
      }
      final existing = room.specialSpace;
      _space = existing ??
          SpecialSpace(kind: SpecialSpaceKind.volume, wallsM2: 0);
      _stair = _space.stair ?? StairwellParams();
      _space.stair = _stair;
      _nameCtrl.text = room.name;
      _syncControllersFromModel();
      setState(() {
        _room = room;
        _project = project;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _syncControllersFromModel() {
    _wallsCtrl.text = _fmt(_space.wallsM2);
    _floorCtrl.text = _fmt(_space.floorM2);
    _ceilingCtrl.text = _fmt(_space.ceilingM2);
    _storeyHCtrl.text = _fmt(_stair.storeyHeightM);
    _totalHCtrl.text = _fmt(_stair.totalHeightM);
    _widthCtrl.text = _fmt(_stair.widthM);
    _depthCtrl.text = _fmt(_stair.depthM);
    _doorsCtrl.text = _fmt(_stair.doorsM2);
    _knownWallsCtrl.text = _fmt(_stair.knownWallsM2);
    _floorsFromCtrl.text = '${_stair.floorsFrom}';
    _floorsToCtrl.text = '${_stair.floorsTo}';
    midLandingCtrl.text = _stair.midLandingDepthM == null
        ? ''
        : _fmt(_stair.midLandingDepthM!);
    botLandingCtrl.text = _stair.bottomLandingDepthM == null
        ? ''
        : _fmt(_stair.bottomLandingDepthM!);
  }

  String _fmt(double v) {
    if (v == 0) return '';
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(2);
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  int _parseInt(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  void _readVolumeFields() {
    _space.wallsM2 = _parse(_wallsCtrl);
    _space.floorM2 = _parse(_floorCtrl);
    _space.ceilingM2 = _parse(_ceilingCtrl);
  }

  void _readStairFields() {
    _stair.storeyHeightM = _parse(_storeyHCtrl);
    _stair.totalHeightM = _parse(_totalHCtrl);
    _stair.widthM = _parse(_widthCtrl);
    _stair.depthM = _parse(_depthCtrl);
    _stair.doorsM2 = _parse(_doorsCtrl);
    _stair.knownWallsM2 = _parse(_knownWallsCtrl);
    _stair.floorsFrom = _parseInt(_floorsFromCtrl, 1);
    _stair.floorsTo = _parseInt(_floorsToCtrl, _stair.floorsFrom);
    final mid = _parse(midLandingCtrl);
    final bot = _parse(botLandingCtrl);
    _stair.midLandingDepthM = mid > 0 ? mid : null;
    if (_stair.landingsSameSize) {
      _stair.bottomLandingDepthM = _stair.midLandingDepthM;
    } else {
      _stair.bottomLandingDepthM = bot > 0 ? bot : null;
    }
    _space.stair = _stair;
    _space.recomputeFromStair();
    _wallsCtrl.text = _fmt(_space.wallsM2);
  }

  void _onFieldChanged() {
    if (_space.kind == SpecialSpaceKind.stairwell) {
      _readStairFields();
    } else {
      _readVolumeFields();
    }
    setState(() {});
  }

  Future<bool> _save({bool silent = false}) async {
    final room = _room;
    if (room == null) return false;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите название')),
        );
      }
      return false;
    }
    if (_space.kind == SpecialSpaceKind.stairwell) {
      _readStairFields();
    } else {
      _readVolumeFields();
    }
    if (!_space.hasAnyArea && _space.kind == SpecialSpaceKind.volume) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите хотя бы одну площадь')),
        );
      }
      return false;
    }
    room.name = name;
    room.specialSpace = _space;
    // Special spaces usually need walls; floor/ceiling optional.
    if (_space.kind == SpecialSpaceKind.stairwell) {
      room.finishIncludeWalls = true;
      if (_space.floorM2 <= 0) room.finishIncludeFloor = false;
      if (_space.ceilingM2 <= 0) room.finishIncludeCeiling = false;
    }
    await AppScope.of(context).projects.updateRoom(room);
    if (!mounted) return true;
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
      setState(() {});
    }
    return true;
  }

  Future<void> _onWillPop(bool didPop, Object? result) async {
    if (didPop) return;
    final ok = await _save(silent: true);
    if (!mounted) return;
    if (!ok) {
      // Keep user on screen — silent save failed (empty name / no areas).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не сохранено — проверьте название и площади'),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _room == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Пространство')),
        body: Center(child: Text(_error ?? 'Ошибка')),
      );
    }
    final theme = Theme.of(context);
    final wallsPreview = _previewWallsM2();
    final isStair = _space.kind == SpecialSpaceKind.stairwell;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onWillPop,
      child: ScreenScaffold(
      appBar: AppBar(
        title: Text(_space.kindLabelRu),
        actions: [
          TextButton(onPressed: () => _save(), child: const Text('Сохранить')),
        ],
      ),
      body: isStair
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: StairSchematicPreview(
                    geometry: _previewStairGeometry(),
                    selectedOpeningIndex: _selectedOpeningIndex,
                    finishSides: _stair.finishSides,
                    onSelectOpening: _stair.inputFocus ==
                            StairInputFocus.knownWallsM2
                        ? null
                        : (i) => setState(() => _selectedOpeningIndex = i),
                    onMoveOpening: _stair.inputFocus ==
                            StairInputFocus.knownWallsM2
                        ? null
                        : _onMoveOpening,
                    onWallLongPress: _stair.inputFocus ==
                            StairInputFocus.knownWallsM2
                        ? null
                        : _onWallLongPress,
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: _stairFormChildren(theme, wallsPreview),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: _volumeFormChildren(theme),
            ),
      ),
    );
  }

  List<Widget> _volumeFormChildren(ThemeData theme) {
    return [
      TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(
          labelText: 'Название',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
      ),
      const SizedBox(height: 16),
      Text('Что вводите', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      _hint(
        'Введите уже известные м² — схему рисовать не нужно. '
        'Пустые поля не попадут в смету.',
      ),
      const SizedBox(height: 12),
      _m2Field(_wallsCtrl, 'Стены, м²', onChanged: (_) => _onFieldChanged()),
      const SizedBox(height: 10),
      _m2Field(_floorCtrl, 'Пол, м²', onChanged: (_) => _onFieldChanged()),
      const SizedBox(height: 10),
      _m2Field(
        _ceilingCtrl,
        'Потолок, м²',
        onChanged: (_) => _onFieldChanged(),
      ),
      ..._finishIncludeAndSave(theme),
    ];
  }

  List<Widget> _stairFormChildren(ThemeData theme, double wallsPreview) {
    final layerCount = _room?.wallFinishLayers.length ?? 0;
    return [
      TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(
          labelText: 'Название',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
      ),
      const SizedBox(height: 12),
      Text('Тип лестницы', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      _stairPlanChips(),
      const SizedBox(height: 12),
      ..._stairFields(),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          title: const Text('Стены (расчёт)'),
          subtitle: Text(
            '${wallsPreview.toStringAsFixed(1)} м² · '
            '${_previewStoreyCount()} эт.'
            '${_stair.openings.isEmpty ? '' : ' · −проёмы'}',
          ),
          trailing: const Icon(Icons.stairs_outlined),
        ),
      ),
      const SizedBox(height: 8),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.layers_outlined),
        title: Text(
          layerCount == 0
              ? 'Слои стен для сметы'
              : 'Слои стен ($layerCount)',
        ),
        subtitle: Text(
          layerCount == 0
              ? 'Без слоёв цена стен в КП/КС = 0'
              : 'Цены слоёв × площадь стен',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openWallLayersEditor,
      ),
      if (_stair.inputFocus != StairInputFocus.knownWallsM2) ...[
        const SizedBox(height: 8),
        ..._openingsSection(theme),
      ] else ...[
        const SizedBox(height: 8),
        _hint(
          'Режим «Знаю м² стен»: проёмы на схеме скрыты — '
          'в смету идёт введённая площадь как есть.',
        ),
      ],
      const SizedBox(height: 10),
      _hint('Пол и потолок лестницы — по желанию (обычно отделка стен).'),
      const SizedBox(height: 8),
      _m2Field(_floorCtrl, 'Пол, м² (необяз.)', onChanged: (_) {
        _space.floorM2 = _parse(_floorCtrl);
        setState(() {});
      }),
      const SizedBox(height: 10),
      _m2Field(_ceilingCtrl, 'Потолок, м² (необяз.)', onChanged: (_) {
        _space.ceilingM2 = _parse(_ceilingCtrl);
        setState(() {});
      }),
      ..._finishIncludeAndSave(theme),
    ];
  }

  Future<void> _openWallLayersEditor() async {
    final room = _room;
    if (room?.id == null) return;
    final ok = await _save(silent: true);
    if (!ok || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FinishRoomScreen(
          projectId: widget.projectId,
          roomId: room!.id!,
          specialLayersOnly: true,
          lockedTabIndex: 1,
          editorTitle: 'Слои · ${room.name}',
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  List<Widget> _finishIncludeAndSave(ThemeData theme) {
    return [
      const SizedBox(height: 16),
      Text('Учитывать в смете', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Стены'),
        value: _room!.finishIncludeWalls,
        onChanged: (v) => setState(() => _room!.finishIncludeWalls = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Пол'),
        value: _room!.finishIncludeFloor,
        onChanged: (v) => setState(() => _room!.finishIncludeFloor = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Потолок'),
        value: _room!.finishIncludeCeiling,
        onChanged: (v) => setState(() => _room!.finishIncludeCeiling = v),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const Text('Сохранить'),
      ),
      if (_project != null) ...[
        const SizedBox(height: 8),
        Text(
          'Слои отделки и расценки — в «Отделка по объекту» '
          '(как у обычных комнат).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  StairwellParams _previewStairParams() {
    final mid = _parse(midLandingCtrl);
    final bot = _parse(botLandingCtrl);
    return StairwellParams(
      plan: _stair.plan,
      inputFocus: _stair.inputFocus,
      floorsFrom: _parseInt(_floorsFromCtrl, _stair.floorsFrom),
      floorsTo: _parseInt(_floorsToCtrl, _stair.floorsTo),
      storeyHeightM: _parse(_storeyHCtrl),
      totalHeightM: _parse(_totalHCtrl),
      widthM: _parse(_widthCtrl),
      depthM: _parse(_depthCtrl),
      finishSides: _stair.finishSides,
      doorsM2: _parse(_doorsCtrl),
      knownWallsM2: _parse(_knownWallsCtrl),
      landingSlabCm: _stair.landingSlabCm,
      treadSlabCm: _stair.treadSlabCm,
      landingsSameSize: _stair.landingsSameSize,
      midLandingDepthM: mid > 0 ? mid : null,
      bottomLandingDepthM: _stair.landingsSameSize
          ? (mid > 0 ? mid : null)
          : (bot > 0 ? bot : null),
      openings: List.of(_stair.openings),
    );
  }

  StairSchematicGeometry? _previewStairGeometry() {
    if (_space.kind != SpecialSpaceKind.stairwell) return null;
    try {
      return _previewStairParams().buildSchematic();
    } catch (e, st) {
      assert(() {
        // ignore: avoid_print
        print('Stair schematic build failed: $e\n$st');
        return true;
      }());
      return null;
    }
  }

  int _previewStoreyCount() => _previewStairParams().storeyCount;

  /// Live walls m² from current fields (no controller writes).
  double _previewWallsM2() {
    if (_space.kind != SpecialSpaceKind.stairwell) {
      return _parse(_wallsCtrl);
    }
    return _previewStairParams().computeWallsM2();
  }

  Widget _hint(String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _m2Field(
    TextEditingController ctrl,
    String label, {
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: NumericInput.decimalKeyboard,
      inputFormatters: NumericInput.decimalFormatters,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }

  Widget _stairPlanChips() {
    return Wrap(
      spacing: 8,
      children: [
        for (final plan in StairPlanKind.values)
          ChoiceChip(
            label: Text(plan.labelRu),
            selected: _stair.plan == plan,
            onSelected: (_) {
              setState(() => _stair.plan = plan);
              _onFieldChanged();
            },
          ),
      ],
    );
  }

  Widget _stairFocusChips() {
    final focus = _stair.inputFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Как задаёте высоту'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in StairInputFocus.values)
              ChoiceChip(
                label: Text(f.labelRu),
                selected: focus == f,
                onSelected: (_) {
                  setState(() => _stair.inputFocus = f);
                  _onFieldChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        _hint(focus.hintRu),
      ],
    );
  }

  List<Widget> _stairFields() {
    final focus = _stair.inputFocus;
    final storeys = _previewStoreyCount();
    return [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _floorsFromCtrl,
              keyboardType: NumericInput.integerKeyboard,
              inputFormatters: NumericInput.integerFormatters,
              decoration: const InputDecoration(
                labelText: 'Этаж с',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _onFieldChanged(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _floorsToCtrl,
              keyboardType: NumericInput.integerKeyboard,
              inputFormatters: NumericInput.integerFormatters,
              decoration: const InputDecoration(
                labelText: 'Этаж по',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _onFieldChanged(),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _stairFocusChips(),
      const SizedBox(height: 12),
      if (focus == StairInputFocus.knownWallsM2) ...[
        _m2Field(
          _knownWallsCtrl,
          'Отделка стен всего, м²',
          onChanged: (_) => _onFieldChanged(),
        ),
        const SizedBox(height: 6),
        _hint('Ш×Д и высота не нужны — только итоговые м² стен.'),
      ],
      if (focus == StairInputFocus.boxAndStoreyHeight ||
          focus == StairInputFocus.totalHeightAndBox) ...[
        Row(
          children: [
            Expanded(
              child: _m2Field(
                _widthCtrl,
                'Ширина Ш, м',
                onChanged: (_) => _onFieldChanged(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _m2Field(
                _depthCtrl,
                'Длина Д, м',
                onChanged: (_) => _onFieldChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _hint(
          'Д = нижняя площадка + марш + промежуточная. Ш — поперёк клетки.',
        ),
        const SizedBox(height: 10),
        if (focus == StairInputFocus.boxAndStoreyHeight)
          _m2Field(
            _storeyHCtrl,
            'Высота одного этажа (пол → пол), м',
            onChanged: (_) => _onFieldChanged(),
          )
        else
          _m2Field(
            _totalHCtrl,
            'Высота всей клетки (эт. с…по), м',
            onChanged: (_) => _onFieldChanged(),
          ),
        const SizedBox(height: 6),
        _hint(
          focus == StairInputFocus.boxAndStoreyHeight
              ? 'Например 3,0 м между плитами. Стены × $storeys эт.'
              : 'Суммарная высота пролёта. Высота этажа = В ÷ $storeys.',
        ),
        const SizedBox(height: 12),
        ..._landingSizeSection(),
        const SizedBox(height: 10),
      ],
      if (focus != StairInputFocus.knownWallsM2) ...[
        Text('Стен под отделку', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        _hint(
          'Жёлтые стороны на плане. 2 — две длинные; 3 — + торец площадки; '
          '4 — все. Периметр × высота × $storeys эт.',
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2 длинные')),
              ButtonSegment(value: 3, label: Text('3 стороны')),
              ButtonSegment(value: 4, label: Text('Все 4')),
            ],
            selected: {
              _stair.finishSides < 2
                  ? 2
                  : (_stair.finishSides > 4 ? 4 : _stair.finishSides),
            },
            onSelectionChanged: (s) {
              setState(() => _stair.finishSides = s.first);
              _onFieldChanged();
            },
          ),
        ),
        const SizedBox(height: 10),
        _m2Field(
          _doorsCtrl,
          'Доп. вычет проёмов на 1 этаж, м² (−)',
          onChanged: (_) => _onFieldChanged(),
        ),
        const SizedBox(height: 4),
        _hint(
          'Вычитается с каждого этажа клетки (× $storeys). '
          'Проёмы на схеме — отдельно.',
        ),
      ],
    ];
  }

  List<Widget> _landingSizeSection() {
    final autoHint = _stair.landingsSameSize
        ? 'Пусто = авто ≈ 18% от Д для обеих.'
        : 'Пусто = авто ≈ 18% от Д для каждой.';
    return [
      Text('Площадки', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Одинак.')),
            ButtonSegment(value: false, label: Text('Разные')),
          ],
          selected: {_stair.landingsSameSize},
          onSelectionChanged: (s) {
            setState(() {
              _stair.landingsSameSize = s.first;
              if (_stair.landingsSameSize) {
                botLandingCtrl.text = midLandingCtrl.text;
              }
            });
            _onFieldChanged();
          },
        ),
      ),
      const SizedBox(height: 10),
      if (_stair.landingsSameSize)
        _m2Field(
          midLandingCtrl,
          'Глубина площадок, м',
          onChanged: (_) => _onFieldChanged(),
        )
      else ...[
        _m2Field(
          midLandingCtrl,
          'Промежуточная, м',
          onChanged: (_) => _onFieldChanged(),
        ),
        const SizedBox(height: 10),
        _m2Field(
          botLandingCtrl,
          'Нижняя, м',
          onChanged: (_) => _onFieldChanged(),
        ),
      ],
      const SizedBox(height: 6),
      _hint(autoHint),
    ];
  }

  List<Widget> _openingsSection(ThemeData theme) {
    return [
      Row(
        children: [
          Expanded(
            child: Text('Проёмы на стенах', style: theme.textTheme.titleSmall),
          ),
          TextButton.icon(
            onPressed: () => _editOpeningDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Добавить'),
          ),
        ],
      ),
      _hint(
        '«Добавить» или удержание стены на Плане / 3D (на «Бок» — только просмотр). '
        'Удержание на проёме — перетаскивание; размеры видны только при перемещении. '
        'При выходе сохраняется само.',
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < _stair.openings.length; i++)
        _openingTile(i, theme),
      if (_stair.openings.isEmpty)
        Text(
          'Пока нет проёмов',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    ];
  }

  Widget _openingTile(int index, ThemeData theme) {
    final o = _stair.openings[index];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        o.kind == 'window' ? Icons.window : Icons.door_front_door_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        '${o.kindLabelRu} · ${o.widthCm.round()}×${o.heightCm.round()} см',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        o.wallLabelRu,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Удалить',
        onPressed: () {
          setState(() {
            _stair.openings.removeAt(index);
            if (_selectedOpeningIndex == index) {
              _selectedOpeningIndex = null;
            } else if (_selectedOpeningIndex != null &&
                _selectedOpeningIndex! > index) {
              _selectedOpeningIndex = _selectedOpeningIndex! - 1;
            }
          });
          _onFieldChanged();
        },
        icon: const Icon(Icons.close),
      ),
      onTap: () {
        setState(() => _selectedOpeningIndex = index);
        _editOpeningDialog(existing: o, index: index);
      },
    );
  }

  void _onMoveOpening(int index, StairWallHit hit) {
    if (index < 0 || index >= _stair.openings.length) return;
    final o = _stair.openings[index];
    final g = _previewStairGeometry();
    final wallLen =
        g == null ? 0.0 : stairWallLengthCm(g, hit.wallIndex);
    final nextStart = g == null
        ? hit.offsetAlongWallCm
        : clampOpeningStartCm(
            start: hit.offsetAlongWallCm,
            wallLen: wallLen,
            openingWidth: o.widthCm,
          );
    // Skip tiny moves — less redraw thrash.
    if (o.wallIndex == hit.wallIndex &&
        (o.offsetAlongWallCm - nextStart).abs() < 0.4) {
      return;
    }
    setState(() {
      o.wallIndex = hit.wallIndex;
      o.offsetAlongWallCm = nextStart;
      if (g != null) {
        o.sillCm = StairwellParams.suggestedSillCmForWall(
          g: g,
          wallIndex: hit.wallIndex,
          offsetAlongCm: nextStart,
          widthCm: o.widthCm,
        );
      }
      _selectedOpeningIndex = index;
    });
  }

  Future<void> _onWallLongPress(StairWallHit hit) async {
    final g = _previewStairGeometry();
    const defaultW = 90.0;
    final centered = g == null
        ? hit.offsetAlongWallCm
        : centeredOpeningStartCm(g, hit.wallIndex, defaultW);
    final sill = g == null
        ? 0.0
        : StairwellParams.suggestedSillCmForWall(
            g: g,
            wallIndex: hit.wallIndex,
            offsetAlongCm: centered,
            widthCm: defaultW,
          );
    await _editOpeningDialog(
      existing: null,
      index: null,
      wallIndex: hit.wallIndex,
      offsetAlongWallCm: centered,
      sillCm: sill,
    );
  }

  Future<void> _editOpeningDialog({
    StairwellOpening? existing,
    int? index,
    int? wallIndex,
    double? offsetAlongWallCm,
    double? sillCm,
  }) async {
    var kind = existing?.kind ?? 'door';
    var wall = existing?.wallIndex ?? wallIndex ?? 0;
    if (wall < 0) wall = 0;
    if (wall > 3) wall = 3;
    final labelCtrl = TextEditingController();
    final wCtrl = TextEditingController(
      text: (existing?.widthCm ?? 90).round().toString(),
    );
    final hCtrl = TextEditingController(
      text: (existing?.heightCm ?? (kind == 'window' ? 140 : 210))
          .round()
          .toString(),
    );
    final defaultSill = sillCm ??
        (existing?.sillCm ?? (kind == 'window' ? 90.0 : 0.0));
    final sillCtrl = TextEditingController(
      text: defaultSill.round().toString(),
    );
    final g = _previewStairGeometry();
    final defaultW = existing?.widthCm ?? 90.0;
    final defaultOffset = offsetAlongWallCm ??
        (g == null
            ? 40.0
            : centeredOpeningStartCm(g, wall, defaultW));
    final offsetCtrl = TextEditingController(
      text: (existing?.offsetAlongWallCm ?? defaultOffset).round().toString(),
    );
    final templates = await loadOpeningTemplates();
    if (!mounted) {
      labelCtrl.dispose();
      wCtrl.dispose();
      hCtrl.dispose();
      sillCtrl.dispose();
      offsetCtrl.dispose();
      return;
    }
    OpeningTemplate? pickedTemplate;
    var saveAsTemplate = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final named = labelCtrl.text.trim().isNotEmpty;
            return AlertDialog(
              title: Text(existing == null ? 'Проём' : 'Изменить проём'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (templates.isNotEmpty) ...[
                      DropdownButtonFormField<OpeningTemplate?>(
                        key: ValueKey(pickedTemplate?.id ?? 'none'),
                        initialValue: pickedTemplate,
                        decoration: const InputDecoration(
                          labelText: 'Из шаблона',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<OpeningTemplate?>(
                            value: null,
                            child: Text('— без шаблона —'),
                          ),
                          for (final t in templates)
                            DropdownMenuItem<OpeningTemplate?>(
                              value: t,
                              child: Text(
                                '${t.name} · ${t.widthCm.round()}×${t.heightCm.round()}',
                              ),
                            ),
                        ],
                        onChanged: (t) {
                          setLocal(() {
                            pickedTemplate = t;
                            if (t == null) return;
                            kind = t.kind;
                            labelCtrl.text = t.name;
                            wCtrl.text = t.widthCm.round().toString();
                            hCtrl.text = t.heightCm.round().toString();
                            sillCtrl.text = t.sillHeightCm.round().toString();
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'door', label: Text('Дверь')),
                          ButtonSegment(value: 'window', label: Text('Окно')),
                        ],
                        selected: {kind},
                        onSelectionChanged: (s) {
                          setLocal(() {
                            kind = s.first;
                            if (existing == null && pickedTemplate == null) {
                              hCtrl.text = kind == 'window' ? '140' : '210';
                              sillCtrl.text = kind == 'window' ? '90' : '0';
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: labelCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setLocal(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Название (для шаблона)',
                        hintText: 'Входная / Межкомнатная…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (named) ...[
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: saveAsTemplate,
                        onChanged: (v) =>
                            setLocal(() => saveAsTemplate = v ?? false),
                        title: const Text('Сохранить как шаблон'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: wall,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Стена',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (var w = 0; w < 4; w++)
                          DropdownMenuItem(
                            value: w,
                            child: Text(
                              StairwellOpening(wallIndex: w).wallLabelRu,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setLocal(() => wall = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: wCtrl,
                            keyboardType: NumericInput.decimalKeyboard,
                            inputFormatters: NumericInput.decimalFormatters,
                            decoration: const InputDecoration(
                              labelText: 'Ширина, см',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: hCtrl,
                            keyboardType: NumericInput.decimalKeyboard,
                            inputFormatters: NumericInput.decimalFormatters,
                            decoration: const InputDecoration(
                              labelText: 'Высота, см',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: sillCtrl,
                      keyboardType: NumericInput.decimalKeyboard,
                      inputFormatters: NumericInput.decimalFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Подоконник / порог, см',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: offsetCtrl,
                      keyboardType: NumericInput.decimalKeyboard,
                      inputFormatters: NumericInput.decimalFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Отступ вдоль стены, см',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(existing == null ? 'Добавить' : 'Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );

    final label = labelCtrl.text.trim();
    final w = double.tryParse(wCtrl.text.replaceAll(',', '.')) ?? 0;
    final h = double.tryParse(hCtrl.text.replaceAll(',', '.')) ?? 0;
    final sill = double.tryParse(sillCtrl.text.replaceAll(',', '.')) ?? 0;
    final off = double.tryParse(offsetCtrl.text.replaceAll(',', '.')) ?? 0;
    final shouldSaveTemplate = saveAsTemplate && label.isNotEmpty;
    labelCtrl.dispose();
    wCtrl.dispose();
    hCtrl.dispose();
    sillCtrl.dispose();
    offsetCtrl.dispose();

    if (ok != true || !mounted) return;
    if (w <= 0 || h <= 0) return;

    if (shouldSaveTemplate) {
      await upsertOpeningTemplate(
        OpeningTemplate(
          id: pickedTemplate?.id ?? newOpeningTemplateId(),
          name: label,
          kind: kind,
          widthCm: w,
          heightCm: h,
          sillHeightCm: sill,
        ),
      );
    }

    final geom = _previewStairGeometry();
    final wallLen = geom == null ? 0.0 : stairWallLengthCm(geom, wall);
    final clampedOff = geom == null
        ? off
        : clampOpeningStartCm(
            start: off,
            wallLen: wallLen,
            openingWidth: w,
          );

    setState(() {
      if (existing != null && index != null) {
        existing.kind = kind;
        existing.wallIndex = wall;
        existing.widthCm = w;
        existing.heightCm = h;
        existing.sillCm = sill;
        existing.offsetAlongWallCm = clampedOff;
        _selectedOpeningIndex = index;
      } else {
        _stair.openings.add(StairwellOpening(
          kind: kind,
          wallIndex: wall,
          widthCm: w,
          heightCm: h,
          sillCm: sill,
          offsetAlongWallCm: clampedOff,
        ));
        _selectedOpeningIndex = _stair.openings.length - 1;
      }
    });
    _onFieldChanged();
  }
}
