import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../domain/finish_layer_pricing.dart';
import '../domain/finish_material_links.dart';
import '../domain/finish_model.dart';
import '../domain/floor_covering.dart';
import '../domain/models.dart';
import '../domain/surface_prep_layers.dart';
import '../domain/work_rates_catalog.dart';
import 'widgets/layer_price_fields.dart';

class _BulkFloorResult {
  const _BulkFloorResult({
    required this.covering,
    required this.pattern,
    required this.widthCm,
    required this.heightCm,
    this.screedDepthCm = defaultScreedDepthCm,
    this.prepLayers = const [],
    this.coveringUnitPrice,
    this.coveringMaterials = const [],
  });

  final FloorCoveringKind covering;
  final FloorLayingPattern pattern;
  final double widthCm;
  final double heightCm;
  final double screedDepthCm;
  final List<SurfacePrepLayer> prepLayers;
  final double? coveringUnitPrice;
  final List<FinishMaterialLink> coveringMaterials;
}

/// Apply floor covering settings to every layout room.
Future<bool> showBulkFloorEditor(
  BuildContext context, {
  required List<Room> rooms,
}) async {
  if (rooms.isEmpty) return false;
  final result = await showModalBottomSheet<_BulkFloorResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _BulkFloorSheet(rooms: rooms),
  );
  if (result == null || !context.mounted) return false;

  final projects = AppScope.of(context).projects;
  var n = 0;
  for (final room in rooms) {
    if (room.id == null) continue;
    room.floorCoveringKind = result.covering.id;
    room.floorLayingPattern = result.covering == FloorCoveringKind.laminate
        ? result.pattern.id
        : FloorLayingPattern.straight.id;
    if (result.covering == FloorCoveringKind.screed) {
      room.floorScreedDepthCm = result.screedDepthCm;
    } else {
      room.finishTileWidthCm = result.widthCm;
      room.finishTileHeightCm = result.heightCm;
    }
    // Always write the edited prep list (empty = clear on all rooms).
    room.floorPrepLayers = clonePrepLayersForRoom(
      result.prepLayers,
      roomId: room.id,
    );
    room.floorCoveringUnitPrice = result.coveringUnitPrice;
    room.floorCoveringMaterials = encodeMaterialLinks(result.coveringMaterials);
    await projects.updateRoom(room);
    n++;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Пол записан в $n помещ. · слоёв подготовки: ${result.prepLayers.length}',
        ),
      ),
    );
  }
  return true;
}

class _BulkFloorSheet extends StatefulWidget {
  const _BulkFloorSheet({required this.rooms});

  final List<Room> rooms;

  @override
  State<_BulkFloorSheet> createState() => _BulkFloorSheetState();
}

class _BulkFloorSheetState extends State<_BulkFloorSheet> {
  late FloorCoveringKind _covering;
  late FloorLayingPattern _pattern;
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;
  late final TextEditingController _depthCtrl;
  late final TextEditingController _priceCtrl;
  late List<SurfacePrepLayer> _prepLayers;
  late List<FinishMaterialLink> _coveringMaterials;

  @override
  void initState() {
    super.initState();
    final seed = widget.rooms.first;
    _covering = FloorCoveringKindX.parse(seed.floorCoveringKind);
    _pattern = FloorLayingPatternX.parse(seed.floorLayingPattern);
    _wCtrl = TextEditingController(text: _fmtSize(seed.finishTileWidthCm));
    _hCtrl = TextEditingController(text: _fmtSize(seed.finishTileHeightCm));
    final depth = seed.floorScreedDepthCm <= 0
        ? defaultScreedDepthCm
        : seed.floorScreedDepthCm;
    _depthCtrl = TextEditingController(text: _fmtSize(depth));
    // Template from any room that already has prep layers (not necessarily first).
    final template = widget.rooms.firstWhere(
      (r) => r.floorPrepLayers.isNotEmpty,
      orElse: () => seed,
    );
    _prepLayers = template.floorPrepLayers
        .map((e) => SurfacePrepLayer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _coveringMaterials = decodeMaterialLinks(seed.floorCoveringMaterials);
    final p = seed.floorCoveringUnitPrice;
    _priceCtrl = TextEditingController(
      text: (p != null && p > 0) ? p.toStringAsFixed(0) : '',
    );
  }

  String _fmtSize(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    _depthCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _applyPreset((double, double) p) {
    _wCtrl.text = _fmtSize(p.$1);
    _hCtrl.text = _fmtSize(p.$2);
  }

  void _submit() {
    final w = double.tryParse(_wCtrl.text.replaceAll(',', '.')) ?? 60;
    final h = double.tryParse(_hCtrl.text.replaceAll(',', '.')) ?? 60;
    final depth = double.tryParse(_depthCtrl.text.replaceAll(',', '.')) ??
        defaultScreedDepthCm;
    final priceRaw = _priceCtrl.text.trim();
    final price = priceRaw.isEmpty
        ? null
        : double.tryParse(priceRaw.replaceAll(',', '.'));
    Navigator.pop(
      context,
      _BulkFloorResult(
        covering: _covering,
        pattern: _pattern,
        widthCm: w,
        heightCm: h,
        screedDepthCm: depth <= 0 ? defaultScreedDepthCm : depth,
        prepLayers: List.of(_prepLayers),
        coveringUnitPrice: price,
        coveringMaterials: List.of(_coveringMaterials),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = _covering == FloorCoveringKind.laminate
        ? laminateBoardPresets
        : floorTilePresets;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Пол для всех помещений (${widget.rooms.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Всё ниже запишется во все ${widget.rooms.length} помещений с чертежом. '
              'Список слоёв — общий шаблон (пустой список очистит подготовку везде).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Text('Покрытие', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<FloorCoveringKind>(
              showSelectedIcon: false,
              segments: [
                for (final k in FloorCoveringKind.values)
                  ButtonSegment(value: k, label: Text(k.labelShortRu)),
              ],
              selected: {_covering},
              onSelectionChanged: (s) {
                setState(() {
                  _covering = s.first;
                  if (_covering == FloorCoveringKind.laminate) {
                    _pattern = FloorLayingPattern.brick;
                    _applyPreset(laminateBoardPresets.first);
                  } else if (_covering == FloorCoveringKind.tile) {
                    _pattern = FloorLayingPattern.straight;
                    _applyPreset(floorTilePresets.first);
                  }
                });
              },
            ),
            if (_covering == FloorCoveringKind.screed) ...[
              const SizedBox(height: 14),
              Text('Толщина стяжки, см', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _depthCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Толщина',
                  suffixText: 'см',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Объём = площадь пола × толщина',
                ),
              ),
            ] else ...[
              if (_covering == FloorCoveringKind.laminate) ...[
                const SizedBox(height: 14),
                Text('Вид укладки', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in FloorLayingPattern.values)
                      ChoiceChip(
                        label: Text(p.labelRu),
                        selected: _pattern == p,
                        onSelected: (_) => setState(() => _pattern = p),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(
                _covering == FloorCoveringKind.laminate
                    ? 'Размер доски (ширина × длина), см'
                    : 'Размер плитки (ширина × длина), см',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in presets)
                  ChoiceChip(
                    label: Text('${p.$1.round()}×${p.$2.round()}'),
                    selected: false,
                    onSelected: (_) => setState(() => _applyPreset(p)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Ширина',
                      suffixText: 'см',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×'),
                ),
                Expanded(
                  child: TextField(
                    controller: _hCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Длина',
                      suffixText: 'см',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            ],
            const SizedBox(height: 16),
            Text(
              'Цена работ покрытия, ₽/м²',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            LayerPriceFields(
              priceCtrl: _priceCtrl,
              section: 'floor',
              suggestName: _covering.labelRu,
              layerKindId: _covering.id,
              materials: _coveringMaterials,
              onMaterialsChanged: (m) =>
                  setState(() => _coveringMaterials = m),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Слои подготовки · ${_prepLayers.length}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final layer = await _editPrepLayerDialog(
                      context,
                      floor: true,
                    );
                    if (layer == null || !mounted) return;
                    setState(() => _prepLayers = [..._prepLayers, layer]);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Слой'),
                ),
              ],
            ),
            Text(
              _prepLayers.isEmpty
                  ? 'Пусто — подготовка очистится во всех помещениях.'
                  : 'Этот список запишется в каждое помещение.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (var i = 0; i < _prepLayers.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_prepLayers[i].displayName(floor: true)),
                subtitle: Text(() {
                  final bits = <String>[
                    if (_prepLayers[i].usesThickness &&
                        _prepLayers[i].thicknessCm > 0)
                      '${_prepLayers[i].thicknessCm.toStringAsFixed(1)} см',
                    if (_prepLayers[i].unitPrice != null &&
                        _prepLayers[i].unitPrice! > 0)
                      '${_prepLayers[i].unitPrice!.toStringAsFixed(0)} ₽/м²',
                  ];
                  return bits.isEmpty ? 'без толщины / цены' : bits.join(' · ');
                }()),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(
                      () => _prepLayers = [..._prepLayers]..removeAt(i),
                    );
                  },
                ),
                onTap: () async {
                  final edited = await _editPrepLayerDialog(
                    context,
                    floor: true,
                    existing: _prepLayers[i],
                  );
                  if (edited == null || !mounted) return;
                  setState(() {
                    _prepLayers = [..._prepLayers];
                    _prepLayers[i] = edited;
                  });
                },
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submit,
              child: Text('Записать во все ${widget.rooms.length} помещ.'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<SurfacePrepLayer?> _editPrepLayerDialog(
  BuildContext context, {
  required bool floor,
  SurfacePrepLayer? existing,
}) async {
  final kindItems = floor
      ? [
          for (final k in FloorPrepKind.values)
            (id: k.id, label: k.labelRu),
        ]
      : [
          for (final k in CeilingPrepKind.values)
            (id: k.id, label: k.labelRu),
        ];
  var kindId = existing?.kindId ?? kindItems.first.id;
  final labelCtrl = TextEditingController(text: existing?.label ?? '');
  final initialThick = existing?.thicknessCm ??
      (floor && kindId == FloorPrepKind.screed.id ? defaultScreedDepthCm : 0.0);
  final thickCtrl = TextEditingController(
    text: initialThick > 0
        ? initialThick.toStringAsFixed(
            initialThick == initialThick.roundToDouble() ? 0 : 1,
          )
        : '',
  );
  final priceCtrl = TextEditingController(
    text: (existing?.unitPrice != null && existing!.unitPrice! > 0)
        ? existing.unitPrice!.toStringAsFixed(0)
        : '',
  );
  var materials = [
    for (final m in existing?.materialLinks ?? const <FinishMaterialLink>[])
      m.copy(),
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final kindLabel = kindItems
            .firstWhere(
              (e) => e.id == kindId,
              orElse: () => kindItems.first,
            )
            .label;
        return AlertDialog(
          title: Text(existing == null ? 'Новый слой' : 'Слой'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: kindId,
                  decoration: const InputDecoration(
                    labelText: 'Тип',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final k in kindItems)
                      DropdownMenuItem(value: k.id, child: Text(k.label)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => kindId = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: labelCtrl,
                  decoration: InputDecoration(
                    labelText: 'Подпись',
                    hintText: kindLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: thickCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Толщина, см',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                LayerPriceFields(
                  priceCtrl: priceCtrl,
                  section: floor ? 'floor' : 'ceiling',
                  suggestName: kindLabel,
                  layerKindId: kindId,
                  materials: materials,
                  onMaterialsChanged: (m) => setLocal(() => materials = m),
                  onChanged: () => setLocal(() {}),
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
              child: const Text('Готово'),
            ),
          ],
        );
      },
    ),
  );
  final label = labelCtrl.text.trim();
  final thickness =
      double.tryParse(thickCtrl.text.replaceAll(',', '.')) ?? 0;
  final priceRaw = priceCtrl.text.trim();
  final unitPrice = priceRaw.isEmpty
      ? null
      : double.tryParse(priceRaw.replaceAll(',', '.'));
  labelCtrl.dispose();
  thickCtrl.dispose();
  priceCtrl.dispose();
  if (ok != true) return null;
  return SurfacePrepLayer(
    kindId: kindId,
    label: label.isEmpty ? null : label,
    enabled: existing?.enabled ?? true,
    thicknessCm: thickness,
    unitPrice: unitPrice,
    rateMatchKey: existing?.rateMatchKey,
    rateName: existing?.rateName,
    priceGroupId: existing?.priceGroupId,
    materialLinks: materials,
  );
}

class _BulkWallsResult {
  const _BulkWallsResult({
    required this.heightCm,
    required this.layers,
  });

  final double heightCm;
  final List<FinishLayer> layers;
}

/// Apply wall finish layers (+ optional height) to every layout room.
Future<bool> showBulkWallsEditor(
  BuildContext context, {
  required List<Room> rooms,
}) async {
  if (rooms.isEmpty) return false;
  final result = await showModalBottomSheet<_BulkWallsResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _BulkWallsSheet(rooms: rooms),
  );
  if (result == null || !context.mounted) return false;

  final projects = AppScope.of(context).projects;
  for (final room in rooms) {
    room.ceilingHeightCm = result.heightCm;
    room.wallFinishLayers = cloneWallLayersForRoom(
      result.layers,
      roomId: room.id,
    );
    await projects.updateRoom(room);
  }
  return true;
}

class _BulkWallsSheet extends StatefulWidget {
  const _BulkWallsSheet({required this.rooms});

  final List<Room> rooms;

  @override
  State<_BulkWallsSheet> createState() => _BulkWallsSheetState();
}

class _BulkWallsSheetState extends State<_BulkWallsSheet> {
  late List<FinishLayer> _layers;
  late final TextEditingController _heightCtrl;
  late final double _seedHeight;

  @override
  void initState() {
    super.initState();
    final seed = widget.rooms.first;
    _seedHeight = seed.ceilingHeightCm;
    _layers = seed.wallFinishLayers
        .map((e) => FinishLayer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _heightCtrl = TextEditingController(text: _seedHeight.round().toString());
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final height = double.tryParse(_heightCtrl.text) ?? _seedHeight;
    Navigator.pop(
      context,
      _BulkWallsResult(heightCm: height, layers: List.of(_layers)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Стены для всех помещений (${widget.rooms.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Слои отделки и высота стен применятся ко всем комнатам с чертежом.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _heightCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Высота стен',
                suffixText: 'см',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Слои отделки',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final layer = await _editLayerDialog(context);
                    if (layer == null || !mounted) return;
                    setState(() => _layers = [..._layers, layer]);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Слой'),
                ),
              ],
            ),
            if (_layers.isEmpty)
              Text(
                'Слои не заданы — можно применить пустой список.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (var i = 0; i < _layers.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_layers[i].displayLabel),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() => _layers = [..._layers]..removeAt(i));
                    },
                  ),
                  onTap: () async {
                    final edited = await _editLayerDialog(
                      context,
                      existing: _layers[i],
                    );
                    if (edited == null || !mounted) return;
                    setState(() {
                      _layers = [..._layers];
                      _layers[i] = edited;
                    });
                  },
                ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submit,
              child: Text('Применить к ${widget.rooms.length} помещ.'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<FinishLayer?> _editLayerDialog(
  BuildContext context, {
  FinishLayer? existing,
}) async {
  final draft = existing ?? FinishLayer(kind: FinishLayerKind.plaster);
  final priceCtrl = TextEditingController(
    text: (draft.unitPrice != null && draft.unitPrice! > 0)
        ? draft.unitPrice!.toStringAsFixed(0)
        : '',
  );
  var materials = [for (final m in draft.materialLinks) m.copy()];
  final result = await showDialog<FinishLayer>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(existing == null ? 'Новый слой' : 'Слой'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<FinishLayerKind>(
                    // ignore: deprecated_member_use
                    value: draft.kind,
                    decoration: const InputDecoration(
                      labelText: 'Тип',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final k in FinishLayerKind.values)
                        DropdownMenuItem(value: k, child: Text(k.labelRu)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() => draft.kind = v);
                    },
                  ),
                  if (draft.kind == FinishLayerKind.paint) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      // ignore: deprecated_member_use
                      value: draft.paintCoats.clamp(1, 3),
                      decoration: const InputDecoration(
                        labelText: 'Слои краски',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1')),
                        DropdownMenuItem(value: 2, child: Text('2')),
                        DropdownMenuItem(value: 3, child: Text('3')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => draft.paintCoats = v);
                      },
                    ),
                  ],
                  if (draft.kind == FinishLayerKind.tile) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Размер плитки настенной, см',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: draft.tileWidthCm.round().toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Ширина',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              draft.tileWidthCm =
                                  double.tryParse(v) ?? draft.tileWidthCm;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: draft.tileHeightCm.round().toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Длина',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              draft.tileHeightCm =
                                  double.tryParse(v) ?? draft.tileHeightCm;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  LayerPriceFields(
                    priceCtrl: priceCtrl,
                    section: 'walls',
                    suggestName: draft.kind.labelRu,
                    layerKindId: draft.kind.id,
                    materials: materials,
                    onMaterialsChanged: (m) => setLocal(() => materials = m),
                    onChanged: () => setLocal(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final raw = priceCtrl.text.trim();
                  draft.unitPrice = raw.isEmpty
                      ? null
                      : double.tryParse(raw.replaceAll(',', '.'));
                  draft.materialLinks = materials;
                  Navigator.pop(ctx, draft);
                },
                child: const Text('Готово'),
              ),
            ],
          );
        },
      );
    },
  );
  priceCtrl.dispose();
  return result;
}

/// Copy wall/floor/ceiling layer prices from [source] onto other layout rooms
/// (or autofill all from catalog when [source] is null).
Future<int> applyFinishLayerPricesAcrossRooms(
  BuildContext context, {
  required List<Room> rooms,
  Room? source,
  bool autofillOnlyEmpty = true,
}) async {
  if (rooms.isEmpty) return 0;
  final projects = AppScope.of(context).projects;
  final catalog = await WorkRatesCatalogStore.ensureLoaded();
  var touched = 0;

  List<Map<String, dynamic>>? wallSrc;
  List<Map<String, dynamic>>? floorSrc;
  List<Map<String, dynamic>>? ceilSrc;
  if (source != null) {
    wallSrc = source.wallFinishLayers
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    floorSrc = source.floorPrepLayers
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    ceilSrc = source.ceilingPrepLayers
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  for (final room in rooms) {
    var changed = false;
    if (wallSrc != null && room.id != source?.id) {
      final layers = wallSrc
          .map((m) => FinishLayer.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      // Fresh per-room group ids so accents don't leak across rooms.
      final remapped = cloneWallLayersForRoom(layers, roomId: room.id)
          .map(FinishLayer.fromJson)
          .toList();
      // Keep target structure if same length/kinds; else replace wholesale.
      final existing =
          room.wallFinishLayers.map(FinishLayer.fromJson).toList();
      if (existing.length == remapped.length &&
          List.generate(
            existing.length,
            (i) => existing[i].kind == remapped[i].kind,
          ).every((e) => e)) {
        for (var i = 0; i < existing.length; i++) {
          existing[i].unitPrice = remapped[i].unitPrice;
          existing[i].rateMatchKey = remapped[i].rateMatchKey;
          existing[i].rateName = remapped[i].rateName;
          existing[i].priceGroupId = remapped[i].priceGroupId;
        }
        room.wallFinishLayers = existing.map((l) => l.toJson()).toList();
      } else {
        room.wallFinishLayers = remapped.map((l) => l.toJson()).toList();
      }
      changed = true;
    } else {
      final walls = room.wallFinishLayers.map(FinishLayer.fromJson).toList();
      final n = autofillWallLayerPrices(
        walls,
        catalog,
        onlyEmpty: autofillOnlyEmpty,
      );
      if (n > 0) {
        room.wallFinishLayers = walls.map((l) => l.toJson()).toList();
        changed = true;
      }
    }

    for (final floor in [true, false]) {
      final src = floor ? floorSrc : ceilSrc;
      final raw = floor ? room.floorPrepLayers : room.ceilingPrepLayers;
      if (src != null && room.id != source?.id) {
        final layers = src
            .map((m) => SurfacePrepLayer.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        final remapped = clonePrepLayersForRoom(layers, roomId: room.id)
            .map(SurfacePrepLayer.fromJson)
            .toList();
        final existing = raw.map(SurfacePrepLayer.fromJson).toList();
        if (existing.length == remapped.length &&
            List.generate(
              existing.length,
              (i) => existing[i].kindId == remapped[i].kindId,
            ).every((e) => e)) {
          for (var i = 0; i < existing.length; i++) {
            existing[i].unitPrice = remapped[i].unitPrice;
            existing[i].rateMatchKey = remapped[i].rateMatchKey;
            existing[i].rateName = remapped[i].rateName;
            existing[i].priceGroupId = remapped[i].priceGroupId;
          }
          final encoded = existing.map((l) => l.toJson()).toList();
          if (floor) {
            room.floorPrepLayers = encoded;
          } else {
            room.ceilingPrepLayers = encoded;
          }
        } else {
          final encoded = remapped.map((l) => l.toJson()).toList();
          if (floor) {
            room.floorPrepLayers = encoded;
          } else {
            room.ceilingPrepLayers = encoded;
          }
        }
        changed = true;
      } else {
        final prep = raw.map(SurfacePrepLayer.fromJson).toList();
        final n = autofillPrepLayerPrices(
          prep,
          catalog,
          floor: floor,
          onlyEmpty: autofillOnlyEmpty,
        );
        if (n > 0) {
          final encoded = prep.map((l) => l.toJson()).toList();
          if (floor) {
            room.floorPrepLayers = encoded;
          } else {
            room.ceilingPrepLayers = encoded;
          }
          changed = true;
        }
      }
    }

    if (source != null && room.id != source.id) {
      room.floorCoveringUnitPrice = source.floorCoveringUnitPrice;
      room.floorCoveringRateMatchKey = source.floorCoveringRateMatchKey;
      room.floorCoveringRateName = source.floorCoveringRateName;
      room.ceilingSystemUnitPrice = source.ceilingSystemUnitPrice;
      room.ceilingSystemRateMatchKey = source.ceilingSystemRateMatchKey;
      room.ceilingSystemRateName = source.ceilingSystemRateName;
      changed = true;
    } else {
      final nCover = autofillCoveringPrices(
        [room],
        catalog,
        onlyEmpty: autofillOnlyEmpty,
      );
      if (nCover > 0) changed = true;
    }

    if (changed) {
      await projects.updateRoom(room);
      touched++;
    }
  }
  return touched;
}

class _BulkCeilingResult {
  const _BulkCeilingResult({
    required this.ceiling,
    required this.susp,
    required this.cell,
    required this.prepLayers,
    required this.systemUnitPrice,
    this.systemMaterials = const [],
  });

  final String ceiling;
  final String susp;
  final String cell;
  final List<SurfacePrepLayer> prepLayers;
  final double? systemUnitPrice;
  final List<FinishMaterialLink> systemMaterials;
}

/// Apply ceiling material defaults to every layout room (+ project defaults).
Future<bool> showBulkCeilingEditor(
  BuildContext context, {
  required Project project,
  required List<Room> rooms,
}) async {
  if (rooms.isEmpty) return false;
  final result = await showModalBottomSheet<_BulkCeilingResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _BulkCeilingSheet(project: project, rooms: rooms),
  );
  if (result == null || !context.mounted) return false;
  if (project.id == null) return false;

  final projects = AppScope.of(context).projects;
  project.materialsCeiling = result.ceiling;
  project.materialsSusp = result.susp;
  project.materialsCell = result.cell;
  await projects.updateProjectMaterials(
    project.id!,
    ceiling: result.ceiling,
    susp: result.susp,
    cell: result.cell,
  );
  var n = 0;
  for (final room in rooms) {
    if (room.id == null) continue;
    room.materialsOverride = false;
    room.materialsCeiling = result.ceiling;
    room.materialsSusp = result.susp;
    room.materialsCell = result.cell;
    room.ceilingPrepLayers = clonePrepLayersForRoom(
      result.prepLayers,
      roomId: room.id,
    );
    room.ceilingSystemUnitPrice = result.systemUnitPrice;
    room.ceilingSystemMaterials = encodeMaterialLinks(result.systemMaterials);
    await projects.updateRoom(room);
    n++;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Потолок записан в $n помещ. · слоёв подготовки: ${result.prepLayers.length}',
        ),
      ),
    );
  }
  return true;
}

class _BulkCeilingSheet extends StatefulWidget {
  const _BulkCeilingSheet({required this.project, required this.rooms});

  final Project project;
  final List<Room> rooms;

  @override
  State<_BulkCeilingSheet> createState() => _BulkCeilingSheetState();
}

class _BulkCeilingSheetState extends State<_BulkCeilingSheet> {
  static const _ceilingOptions = ['Армстронг', 'Грильято', 'GL'];
  static const _suspOptions = ['Подвес 0,5', 'Подвес 1', 'Подвес 1,5'];
  static const _cellOptions = ['50x50', '75x75', '100x100'];

  late String _ceiling;
  late String _susp;
  late String _cell;
  late List<SurfacePrepLayer> _prepLayers;
  late List<FinishMaterialLink> _systemMaterials;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    final seed = widget.rooms.first;
    _ceiling = widget.project.materialsCeiling ??
        seed.materialsCeiling ??
        'Армстронг';
    _susp =
        widget.project.materialsSusp ?? seed.materialsSusp ?? 'Подвес 0,5';
    _cell = widget.project.materialsCell ?? seed.materialsCell ?? '50x50';
    if (!_ceilingOptions.contains(_ceiling)) _ceiling = _ceilingOptions.first;
    if (!_suspOptions.contains(_susp)) _susp = _suspOptions.first;
    if (!_cellOptions.contains(_cell)) _cell = _cellOptions.first;
    final template = widget.rooms.firstWhere(
      (r) => r.ceilingPrepLayers.isNotEmpty,
      orElse: () => seed,
    );
    _prepLayers = template.ceilingPrepLayers
        .map((e) => SurfacePrepLayer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _systemMaterials = decodeMaterialLinks(seed.ceilingSystemMaterials);
    final p = seed.ceilingSystemUnitPrice;
    _priceCtrl = TextEditingController(
      text: (p != null && p > 0) ? p.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final priceRaw = _priceCtrl.text.trim();
    final price = priceRaw.isEmpty
        ? null
        : double.tryParse(priceRaw.replaceAll(',', '.'));
    Navigator.pop(
      context,
      _BulkCeilingResult(
        ceiling: _ceiling,
        susp: _susp,
        cell: _cell,
        prepLayers: List.of(_prepLayers),
        systemUnitPrice: price,
        systemMaterials: List.of(_systemMaterials),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Потолок для всех помещений (${widget.rooms.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Всё ниже запишется во все ${widget.rooms.length} помещений. '
              'Пустой список слоёв очистит подготовку везде.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _ceiling,
              decoration: const InputDecoration(
                labelText: 'Тип потолка',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final o in _ceilingOptions)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _ceiling = v);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _susp,
              decoration: const InputDecoration(
                labelText: 'Подвес',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final o in _suspOptions)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _susp = v);
              },
            ),
            if (_ceiling == 'Грильято' || _ceiling == 'GL') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _cell,
                decoration: const InputDecoration(
                  labelText: 'Ячейка',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final o in _cellOptions)
                    DropdownMenuItem(value: o, child: Text(o)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _cell = v);
                },
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Цена монтажа системы, ₽/м²',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            LayerPriceFields(
              priceCtrl: _priceCtrl,
              section: 'ceiling',
              suggestName: _ceiling,
              layerKindId: 'system',
              materials: _systemMaterials,
              onMaterialsChanged: (m) =>
                  setState(() => _systemMaterials = m),
              onChanged: () => setState(() {}),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Слои подготовки · ${_prepLayers.length}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final layer = await _editPrepLayerDialog(
                      context,
                      floor: false,
                    );
                    if (layer == null || !mounted) return;
                    setState(() => _prepLayers = [..._prepLayers, layer]);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Слой'),
                ),
              ],
            ),
            Text(
              _prepLayers.isEmpty
                  ? 'Пусто — подготовка очистится во всех помещениях.'
                  : 'Этот список запишется в каждое помещение.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (var i = 0; i < _prepLayers.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_prepLayers[i].displayName(floor: false)),
                subtitle: Text(
                  _prepLayers[i].unitPrice != null &&
                          _prepLayers[i].unitPrice! > 0
                      ? '${_prepLayers[i].unitPrice!.toStringAsFixed(0)} ₽/м²'
                      : 'без цены',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(
                      () => _prepLayers = [..._prepLayers]..removeAt(i),
                    );
                  },
                ),
                onTap: () async {
                  final edited = await _editPrepLayerDialog(
                    context,
                    floor: false,
                    existing: _prepLayers[i],
                  );
                  if (edited == null || !mounted) return;
                  setState(() {
                    _prepLayers = [..._prepLayers];
                    _prepLayers[i] = edited;
                  });
                },
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submit,
              child: Text('Записать во все ${widget.rooms.length} помещ.'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}
