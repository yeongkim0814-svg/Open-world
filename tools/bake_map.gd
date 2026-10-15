extends SceneTree
## 색칠 지도 굽기. 사용: godot --headless -s tools/bake_map.gd -- <map>
## 읽기: res://maps/<map>/{height,heightmap,zones,paths,markers}.png (zones·paths 는 없어도 됨)
##       heightmap.png (선택) = baked/height.png 와 같은 RGB8 16비트 높이 (R 상위·G 하위, min_h~max_h).
##       있으면 height.png 대신 쓰고 (height.png 는 없어도 됨), 크기가 다르면 쌍선형으로 맞춘다.
##       moat.png (선택) = 해자 모양 (0 없음·128 물·255 탑 섬) — 원형 저수호·탑 도장 대신.
##       res://maps/<map>/map.json (선택): {"size", "world", "min_h", "max_h", "smooth_radius", "edge_sea",
##       "peak_height", "peak_radius", "summit_radius", "lake_radius", "tower_radius"}
##       size = 지도 이미지를 맞출 격자 크기 (기본 1024), world = 세계 폭 m (기본 1024)
## 쓰기: res://maps/<map>/baked/{height.png, zones.png, paths.png, markers.json, preview.png, meta.json, moat.png(해자가 있을 때)}
## 오류가 있으면 메시지를 출력하고 종료 코드 1 (아무것도 쓰지 않음).

const DEFAULT_SIZE := 1024
const DEFAULT_WORLD := 1024.0
const LAYER_NAMES := ["height", "heightmap", "zones", "paths", "markers", "moat"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("사용법: godot --headless -s tools/bake_map.gd -- <map>")
		quit(1)
		return
	var map_name: String = args[0]
	var dir := "res://maps/%s" % map_name
	var t0 := Time.get_ticks_msec()

	var cfg = _read_cfg("%s/map.json" % dir)
	if cfg == null:
		quit(1)
		return
	var size := int(cfg.get("size", DEFAULT_SIZE))
	var world := float(cfg.get("world", DEFAULT_WORLD))
	if size < 16 or world <= 0.0:
		printerr("오류: map.json 의 size·world 가 올바르지 않습니다 (%d, %s)" % [size, world])
		quit(1)
		return
	print("설정 size=%d world=%s %s" % [size, world, JSON.stringify(cfg)])

	var layers := {}
	for name in LAYER_NAMES:
		var path := "%s/%s.png" % [dir, name]
		var abs_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(abs_path):
			continue
		var img := Image.load_from_file(abs_path)
		if img == null or img.is_empty():
			printerr("오류: %s 를 읽지 못했습니다" % path)
			quit(1)
			return
		layers[name] = img
		print("읽음 %s (%d×%d)" % [path, img.get_width(), img.get_height()])
	var t1 := Time.get_ticks_msec()

	var baked := MapBaker.bake(layers, size, world, cfg)
	var t2 := Time.get_ticks_msec()
	for w in baked["warnings"]:
		print(w)
	if not baked["errors"].is_empty():
		for e in baked["errors"]:
			printerr("오류: %s/ — %s" % [dir, e])
		quit(1)
		return

	var out_dir := "%s/baked" % dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ok := true
	var meta: Dictionary = baked["meta"]
	ok = _save(MapBaker.encode_height(baked["height"], size, meta["min_h"], meta["max_h"]), "%s/height.png" % out_dir) and ok
	ok = _save(Image.create_from_data(size, size, false, Image.FORMAT_R8, baked["zones"]), "%s/zones.png" % out_dir) and ok
	ok = _save(Image.create_from_data(size, size, false, Image.FORMAT_R8, baked["paths"]), "%s/paths.png" % out_dir) and ok
	ok = _save(MapBaker.preview(baked, size), "%s/preview.png" % out_dir) and ok
	var moat_path := ProjectSettings.globalize_path("%s/moat.png" % out_dir)
	if not baked["moat"].is_empty():
		ok = _save(MapBaker.encode_moat(baked["moat"], size), "%s/moat.png" % out_dir) and ok
	elif FileAccess.file_exists(moat_path):
		DirAccess.remove_absolute(moat_path)      # 옛 해자 모양이 남아 게임이 잘못 읽지 않게
	ok = _write_text(JSON.stringify(baked["markers"], "\t"), "%s/markers.json" % out_dir) and ok
	ok = _write_text(JSON.stringify(meta, "\t"), "%s/meta.json" % out_dir) and ok
	var t3 := Time.get_ticks_msec()
	print("굽기 완료 %s — 표식 %d개 | 읽기 %d ms · 굽기 %d ms · 저장 %d ms · 합계 %d ms" % [
		map_name, baked["markers"].size(), t1 - t0, t2 - t1, t3 - t2, t3 - t0])
	quit(0 if ok else 1)


func _save(img: Image, path: String) -> bool:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("오류: %s 저장 실패 (%d)" % [path, err])
		return false
	return true


## map.json 읽기. 없으면 빈 설정 {}, 깨졌으면 오류 출력 후 null.
func _read_cfg(path: String) -> Variant:
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(abs_path))
	if not parsed is Dictionary:
		printerr("오류: %s 는 JSON 객체여야 합니다" % path)
		return null
	return parsed


func _write_text(text: String, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("오류: %s 를 쓰지 못했습니다" % path)
		return false
	f.store_string(text)
	f.close()
	return true
