/// Layer visibility for layout editor (mirrors export toggles where applicable).
class LayoutLayerVisibility {
  const LayoutLayerVisibility({
    this.walls = true,
    this.grid = true,
    this.guides = true,
    this.lights = true,
    this.floor = false,
    this.notes = false,
    this.wallDims = true,
    this.tileDims = true,
  });

  final bool walls;
  final bool grid;
  final bool guides;
  final bool lights;
  final bool floor;
  final bool notes;
  final bool wallDims;
  final bool tileDims;

  LayoutLayerVisibility copyWith({
    bool? walls,
    bool? grid,
    bool? guides,
    bool? lights,
    bool? floor,
    bool? notes,
    bool? wallDims,
    bool? tileDims,
  }) {
    return LayoutLayerVisibility(
      walls: walls ?? this.walls,
      grid: grid ?? this.grid,
      guides: guides ?? this.guides,
      lights: lights ?? this.lights,
      floor: floor ?? this.floor,
      notes: notes ?? this.notes,
      wallDims: wallDims ?? this.wallDims,
      tileDims: tileDims ?? this.tileDims,
    );
  }

  Map<String, dynamic> toJson() => {
        'walls': walls,
        'grid': grid,
        'guides': guides,
        'lights': lights,
        'floor': floor,
        'notes': notes,
        'wall_dims': wallDims,
        'tile_dims': tileDims,
      };

  static LayoutLayerVisibility fromJson(Map<String, dynamic>? j) {
    if (j == null || j.isEmpty) return const LayoutLayerVisibility();
    return LayoutLayerVisibility(
      walls: j['walls'] as bool? ?? true,
      grid: j['grid'] as bool? ?? true,
      guides: j['guides'] as bool? ?? true,
      lights: j['lights'] as bool? ?? true,
      floor: j['floor'] as bool? ?? false,
      notes: j['notes'] as bool? ?? false,
      wallDims: j['wall_dims'] as bool? ?? true,
      tileDims: j['tile_dims'] as bool? ?? true,
    );
  }
}
