extends SceneTree
## 색칠 지도 굽기. 사용: godot --headless -s tools/bake_map.gd -- <map>
## 읽기: res://maps/<map>/{height,zones,paths,markers}.png (zones·paths 는 없어도 됨)
## 쓰기: res://maps/<map>/baked/{height.png, zones.png, paths.png, markers.json, preview.png}
## 오류가 있으면 메시지를 출력하고 종료 코드 1 (아무것도 쓰지 않음).

const SIZE := 1024
const WORLD := 1024.0
const LAYER_NAMES := ["height", "zones", "paths", "markers"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("사용법: godot --headless -s tools/bake_map.gd -- <map>")
		quit(1)
		return
	var map_name: String = args[0]
	var dir := "res://maps/%s" % map_name
	var t0 := Time.get_ticks_msec()

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

	var baked := MapBaker.bake(layers, SIZE, WORLD)
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
	ok = _save(MapBaker.encode_height(baked["height"], SIZE), "%s/height.png" % out_dir) and ok
	ok = _save(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_R8, baked["zones"]), "%s/zones.png" % out_dir) and ok
	ok = _save(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_R8, baked["paths"]), "%s/paths.png" % out_dir) and ok
	ok = _save(MapBaker.preview(baked, SIZE), "%s/preview.png" % out_dir) and ok
	var f := FileAccess.open("%s/markers.json" % out_dir, FileAccess.WRITE)
	if f == null:
		printerr("오류: markers.json 을 쓰지 못했습니다")
		ok = false
	else:
		f.store_string(JSON.stringify(baked["markers"], "\t"))
		f.close()
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
