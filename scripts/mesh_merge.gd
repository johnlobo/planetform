extends RefCounted
## Junta las piezas fijas de una construcción en pocas mallas para dibujarlas
## con muy pocas llamadas. El color de cada pieza pasa a los vértices; piezas
## con el mismo brillo y emisión comparten material, así que una máquina de 20
## piezas se dibuja con 3 o 4 llamadas en vez de 20.

## Las piezas más pequeñas que esto (en metros) no proyectan sombra y se
## dejan de ver pasados SMALL_RANGE metros.
const SMALL_SIZE := 0.35
const SMALL_RANGE := 80.0

static var _materials := {}


## true si la pieza se puede juntar con otras: malla simple con material
## opaco y sin texturas. "keep" son los materiales que cambian mientras se juega.
static func can_merge(part: MeshInstance3D, keep: Array = []) -> bool:
	if not part.visible or part.get_child_count() > 0 or part.has_meta("sample_drone"):
		return false
	if not (part.mesh is PrimitiveMesh):
		return false
	var material := part.material_override as StandardMaterial3D
	if material == null or material in keep:
		return false
	return material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_texture == null \
		and not material.vertex_color_use_as_albedo


## Junta las piezas en mallas hijas de "parent" (que es su padre actual) y
## borra las piezas.
static func merge(parent: Node3D, parts: Array) -> void:
	# Un grupo por (tamaño de la pieza, material); cada uno lleva sus arrays.
	var groups := {}
	for part: MeshInstance3D in parts:
		var material := part.material_override as StandardMaterial3D
		var arrays: Array = part.mesh.get_mesh_arrays()
		var xform := part.transform
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		var moved := PackedVector3Array()
		moved.resize(vertices.size())
		for k in vertices.size():
			var v := xform * vertices[k]
			moved[k] = v
			low = low.min(v)
			high = high.max(v)
		var small := maxf(high.x - low.x, maxf(high.y - low.y, high.z - low.z)) < SMALL_SIZE
		var key := [small, material.metallic, material.roughness, material.emission_enabled, material.emission,
			material.emission_energy_multiplier, material.shading_mode, material.cull_mode]
		if not groups.has(key):
			groups[key] = {"small": small, "material": material, "verts": PackedVector3Array(), "normals": PackedVector3Array(),
				"colors": PackedColorArray(), "indices": PackedInt32Array()}
		var group: Dictionary = groups[key]
		var base: int = group["verts"].size()
		var normal_basis := xform.basis.inverse().transposed()
		var color := material.albedo_color
		for k in vertices.size():
			group["verts"].append(moved[k])
			group["normals"].append((normal_basis * normals[k]).normalized())
			group["colors"].append(color)
		for index in indices:
			group["indices"].append(index + base)
	for part in parts:
		parent.remove_child(part)
		part.free()
	# Una malla con los grupos grandes (con sombra) y otra con los pequeños.
	for small in [false, true]:
		var mesh := ArrayMesh.new()
		for group in groups.values():
			if group["small"] != small:
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = group["verts"]
			arrays[Mesh.ARRAY_NORMAL] = group["normals"]
			arrays[Mesh.ARRAY_COLOR] = group["colors"]
			arrays[Mesh.ARRAY_INDEX] = group["indices"]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _shared_material(group["material"]))
		if mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Merged"
		instance.mesh = mesh
		if small:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = SMALL_RANGE
		parent.add_child(instance)


## Material de vértices con las propiedades de "source" (menos el color), uno
## por combinación y compartido por todas las construcciones.
static func _shared_material(source: StandardMaterial3D) -> StandardMaterial3D:
	var key := [source.metallic, source.roughness, source.emission_enabled, source.emission,
		source.emission_energy_multiplier, source.shading_mode, source.cull_mode]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.metallic = source.metallic
	material.roughness = source.roughness
	material.emission_enabled = source.emission_enabled
	material.emission = source.emission
	material.emission_energy_multiplier = source.emission_energy_multiplier
	material.shading_mode = source.shading_mode
	material.cull_mode = source.cull_mode
	_materials[key] = material
	return material
