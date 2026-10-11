class_name StylePalette
extends RefCounted
## 스타일 팔레트 (설계서 2026-10-11-stylized-graphics-design.md 5장 시작값). 고갈(0) ↔ 회복(1).
## 셰이더 머티리얼의 색 uniform은 이 표에서 채운다 (한 곳에서 관리).

const DEPLETED := {
	"sky_zenith": Color("#8A9BA8"), "sky_horizon": Color("#AABAC5"),
	"grass": Color("#A5AC91"), "grass_tip": Color("#B8BCA4"),
	"ground": Color("#C8C2AC"), "sand": Color("#CFC9B6"), "rock": Color("#8C918F"),
	"foliage": Color("#9AA391"), "flower": Color("#C4C2B8"),
	"water_shallow": Color("#9FB1B3"), "water_deep": Color("#6E8288"),
}
const RESTORED := {
	"sky_zenith": Color("#4F86C0"), "sky_horizon": Color("#C6DDEC"),
	"grass": Color("#6FA35A"), "grass_tip": Color("#9CC46E"),
	"ground": Color("#B9A27E"), "sand": Color("#D9C9A0"), "rock": Color("#8E8A82"),
	"foliage": Color("#6E9A6A"), "flower": Color("#EED36A"),
	"water_shallow": Color("#6FB8B9"), "water_deep": Color("#2F6F8F"),
}
## 항상 고채도 (회복값과 무관)
const LIFE := Color("#76C9C3")
const WARN_YELLOW := Color("#FFD933")
const WARN_RED := Color("#FF2619")
const CORE := Color("#4DE6FF")


static func color(key: String, recovery: float) -> Color:
	return (DEPLETED[key] as Color).lerp(RESTORED[key], clampf(recovery, 0.0, 1.0))
