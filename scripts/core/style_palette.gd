class_name StylePalette
extends RefCounted
## 스타일 팔레트 (설계서 2026-10-11-stylized-graphics-design.md 5장 시작값). 고갈(0) ↔ 회복(1).
## 셰이더 머티리얼의 색 uniform은 이 표에서 채운다 (한 곳에서 관리).
## B2 개정(설계서 2026-10-13 9.2): 회복 0 에서 잎(따뜻한 황갈)·바위(차가운 청회색)·줄기·윗면 이끼를 밝기·색온도로 가른다.

const DEPLETED := {
	"sky_zenith": Color("#8A9BA8"), "sky_horizon": Color("#AABAC5"),
	"grass": Color("#A5AC91"), "grass_tip": Color("#B8BCA4"),
	"ground": Color("#B5B19E"), "sand": Color("#CFC9B6"), "rock": Color("#7E858C"),
	"foliage": Color("#A89270"), "trunk": Color("#5E5045"), "moss": Color("#9E9A86"), "flower": Color("#C4C2B8"),
	"water_shallow": Color("#9FB1B3"), "water_deep": Color("#6E8288"),
	# 구역 땅 색 (초원 = grass, 해안 = sand)과 길
	"zone_broadleaf": Color("#9EA28E"), "zone_conifer": Color("#8F9786"), "zone_wetland": Color("#9AA79C"),
	"zone_highland": Color("#A3A39C"), "zone_wasteland": Color("#B3A48E"),
	"path_dirt": Color("#BDB39C"), "path_paved": Color("#A9A9A3"),
}
const RESTORED := {
	"sky_zenith": Color("#4F86C0"), "sky_horizon": Color("#B7D3EA"),
	"grass": Color("#6FA35A"), "grass_tip": Color("#9CC46E"),
	"ground": Color("#B9A27E"), "sand": Color("#D9C9A0"), "rock": Color("#8E8A82"),
	"foliage": Color("#6E9A6A"), "trunk": Color("#6B5640"), "moss": Color("#6F8F55"), "flower": Color("#EED36A"),
	"water_shallow": Color("#6FB8B9"), "water_deep": Color("#2F6F8F"),
	"zone_broadleaf": Color("#5F9450"), "zone_conifer": Color("#4B6B45"), "zone_wetland": Color("#5E8F6E"),
	"zone_highland": Color("#8E8C7A"), "zone_wasteland": Color("#7FA85A"),   # 황무지는 회복하면 초원 쪽 초록
	"path_dirt": Color("#A0855E"), "path_paved": Color("#9C978C"),
}
## 항상 고채도 (회복값과 무관)
const LIFE := Color("#76C9C3")
const WARN_YELLOW := Color("#FFD933")
const WARN_RED := Color("#FF2619")
const CORE := Color("#4DE6FF")


static func color(key: String, recovery: float) -> Color:
	return (DEPLETED[key] as Color).lerp(RESTORED[key], clampf(recovery, 0.0, 1.0))
