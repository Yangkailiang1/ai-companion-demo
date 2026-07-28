# Roadmap: S4.2
# Responsibility: Upload an already generated NavigationMesh after its region
# enters World3D; does not generate polygons or select navigation targets.
# Collaborators: ParametricNavigationFactory, NavigationServer3D
# Tests: scripts/debug/parametric_nav_waypoint_check.gd

extends NavigationRegion3D


## [S4.2] 显式上传运行时逐多边形构造的网格，并刷新所在导航地图。
func _ready() -> void:
	if navigation_mesh == null:
		return
	NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)
	var map_rid := get_navigation_map()
	if map_rid != RID():
		NavigationServer3D.map_force_update(map_rid)
