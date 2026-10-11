class_name VegCatalog
extends RefCounted
## 식생·바위 메시 카탈로그: VegPlacement.mesh_ids() 의 모든 id 를 한 번 만들어 재질을 입힌다.
## 풀 변형 _0/_1 = GrassGen.build(kind, variant) (variant 마다 다른 시드 = 다른 잎 배치).
## 덤불 shrub_0..3 = TreeGen SHRUB 시드 4개, 나무 *_0..2 = 시드 3개 (LOD0 + LOD1).
## 나무·덤불은 줄기·잎 두 면을 한 면으로 합친다 (UV.x = 1 줄기) — MultiMesh 하나 = 그리기 호출 1개.

const LIT := preload("res://shaders/style_lit.gdshader")
const FOLIAGE := preload("res://shaders/style_foliage.gdshader")
const ROCK := preload("res://shaders/style_rock.gdshader")

const TREE_SEED_BASE := 11   ## 나무 시드 = BASE + 변형 번호 × 7
const SHRUB_SEED_BASE := 5
const ROCK_SEED_BASE := 30

var _meshes := {}        ## id → ArrayMesh (LOD0)
var _tree_lod1 := {}     ## id → ArrayMesh (LOD1, 나무만)
var _shapes := {}        ## 바위 id → ConvexPolygonShape3D
var _trunks := {}        ## 나무 id → Vector2(반경, 높이)
var _ids := PackedStringArray()


func _init() -> void:
	var grass_mat := _foliage("grass", "grass_tip", true, 40.0, 55.0)
	var shrub_mat := _foliage("foliage", "grass_tip", true, 120.0, 160.0)
	shrub_mat.set_shader_parameter("density_depleted", 1.0)
	_trunk_color(shrub_mat)
	var leaves := _foliage("foliage", "grass_tip", true, 100000.0, 100001.0)
	leaves.set_shader_parameter("density_depleted", 1.0)   # 나무는 회복 전에도 서 있다 (색·바람만 변화)
	leaves.set_shader_parameter("height_depleted", 1.0)
	leaves.set_shader_parameter("wind_strength", 0.02)
	_trunk_color(leaves)
	var rock_mat := _rock()
	for id in VegPlacement.mesh_ids():
		var parts := id.split("_")
		var variant := int(parts[parts.size() - 1])
		_ids.append(id)
		match parts[0]:
			"grass":
				var m := GrassGen.build(VegPlacement.GRASS_KINDS.find(parts[1]), variant)
				m.surface_set_material(0, grass_mat)
				_meshes[id] = m
			"shrub":
				var m := _tree(SHRUB_SEED_BASE + variant * 7, TreeGen.Kind.SHRUB, 0, shrub_mat)
				_meshes[id] = m
			"tree":
				var kind: int = [TreeGen.Kind.ROUND, TreeGen.Kind.COLUMN, TreeGen.Kind.SPREAD][VegPlacement.TREE_KINDS.find(parts[1])]
				var sd := TREE_SEED_BASE + variant * 7
				var src := TreeGen.build(sd, kind, 0)
				# 줄기 = 면 0 의 AABB (반경 = 가로 반폭, 높이 = 세로) — 합치기 전에 잰다
				_trunks[id] = _trunk_dims(src)
				_meshes[id] = _merged(src, leaves)
				_tree_lod1[id] = _tree(sd, kind, 1, leaves)
			"rock":
				var m := RockGen.build(ROCK_SEED_BASE + variant, VegPlacement.ROCK_KINDS.find(parts[1]))
				m.surface_set_material(0, rock_mat)
				_meshes[id] = m
				_shapes[id] = m.create_convex_shape(true, true)


func mesh(id: String, lod := 0) -> ArrayMesh:
	if lod >= 1 and _tree_lod1.has(id):
		return _tree_lod1[id]
	return _meshes.get(id)


func ids() -> PackedStringArray:
	return _ids


## 바위 볼록 충돌 모양 (단위 크기, 호출 측이 크기 배율 적용). 같은 id = 같은 객체.
func rock_shape(id: String) -> ConvexPolygonShape3D:
	return _shapes.get(id)


## 나무 줄기 (반경, 높이) — 단위 크기
func trunk(id: String) -> Vector2:
	return _trunks.get(id, Vector2.ZERO)


# ---------- 내부 ----------

func _tree(sd: int, kind: int, lod: int, mat: Material) -> ArrayMesh:
	return _merged(TreeGen.build(sd, kind, lod), mat)


## TreeGen 두 면(0 줄기, 1 잎)을 한 면으로: 정점·법선·색을 잇고 UV.x = 1 로 줄기 정점 표시 (색인 없는 메시)
static func _merged(src: ArrayMesh, mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		verts.append_array(v)
		norms.append_array(a[Mesh.ARRAY_NORMAL])
		cols.append_array(a[Mesh.ARRAY_COLOR])
		var flag := Vector2(1.0 if si == 0 else 0.0, 0.0)
		var start := uvs.size()
		uvs.resize(start + v.size())
		for i in v.size():
			uvs[start + i] = flag
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


## 줄기색 = 팔레트 trunk (잎과 분리), 회복 0 에서 수관을 15 % 오그라뜨려 시든 나무로 읽히게 한다 (B2 9.2)
func _trunk_color(m: ShaderMaterial) -> void:
	m.set_shader_parameter("has_trunk", true)
	m.set_shader_parameter("trunk_depleted", StylePalette.DEPLETED["trunk"])
	m.set_shader_parameter("trunk_restored", StylePalette.RESTORED["trunk"])
	m.set_shader_parameter("canopy_shrink", 0.15)


## 바위 재질: 몸체 + 윗면 이끼 (style_rock)
func _rock() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK
	m.set_shader_parameter("color_depleted", StylePalette.DEPLETED["rock"])
	m.set_shader_parameter("color_restored", StylePalette.RESTORED["rock"])
	m.set_shader_parameter("moss_depleted", StylePalette.DEPLETED["moss"])
	m.set_shader_parameter("moss_restored", StylePalette.RESTORED["moss"])
	return m


func _trunk_dims(m: ArrayMesh) -> Vector2:
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in vs:
		lo = lo.min(v)
		hi = hi.max(v)
	return Vector2(maxf(hi.x - lo.x, hi.z - lo.z) * 0.5, hi.y - lo.y)


func _lit(key: String, light := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LIT
	m.set_shader_parameter("color_depleted", StylePalette.DEPLETED[key] * light)
	m.set_shader_parameter("color_restored", StylePalette.RESTORED[key] * light)
	return m


func _foliage(body: String, tip: String, tint: bool, fade_start: float, fade_end: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE
	m.set_shader_parameter("color_depleted", StylePalette.DEPLETED[body])
	m.set_shader_parameter("color_restored", StylePalette.RESTORED[body])
	m.set_shader_parameter("tip_depleted", StylePalette.DEPLETED[tip])
	m.set_shader_parameter("tip_restored", StylePalette.RESTORED[tip])
	m.set_shader_parameter("flower_depleted", StylePalette.DEPLETED.flower)
	m.set_shader_parameter("flower_restored", StylePalette.RESTORED.flower)
	m.set_shader_parameter("instance_tint", tint)
	m.set_shader_parameter("fade_start", fade_start)
	m.set_shader_parameter("fade_end", fade_end)
	return m
