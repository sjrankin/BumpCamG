class_name SurfaceMaterials
extends RefCounted
## Named surface finishes, each a combination of the Metallic and Roughness settings.

const PRESETS := {
	"Matte": {"metallic": 0.0, "roughness": 0.95},
	"Satin": {"metallic": 0.0, "roughness": 0.55},
	"Glossy": {"metallic": 0.0, "roughness": 0.15},
	"Metallic": {"metallic": 0.9, "roughness": 0.3},
}
## Shown when the sliders have been set to something that is not one of the presets.
const CUSTOM := "Custom"
const NAMES: Array[String] = ["Matte", "Satin", "Glossy", "Metallic", "Custom"]


## The preset that exactly matches these values, or "Custom".
static func name_for(metallic: float, roughness: float) -> String:
	for preset_name: String in PRESETS:
		var preset: Dictionary = PRESETS[preset_name]
		if is_equal_approx(float(preset["metallic"]), metallic) and is_equal_approx(float(preset["roughness"]), roughness):
			return preset_name
	return CUSTOM
