extends AudioStreamPlayer3D

class_name LandingPlayer

@export var generic_fallback_landing_profile : AudioStreamRandomizer
@export var landing_material_library : FootstepMaterialLibrary


var last_result

func _ready():
	if not generic_fallback_landing_profile:
		printerr("FootstepSurfaceDetector - No generic fallback footstep profile is assigned")


func play_landing():
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -1, 0))
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		last_result = result
		if _play_by_landing_surface(result.collider):
			return
		elif _play_by_material(result.collider):
			return
		# If no material, play generic landing sound
		else:
			_play_landing(generic_fallback_landing_profile)

func _play_by_landing_surface(collider : Node3D) -> bool:
	# Check for landing surface as a child of the collider
	var landing_surface_child : AudioStreamRandomizer = _get_landing_surface_child(collider)
	# If a child landing surface was found, play the sound defined by it
	if landing_surface_child:
		_play_landing(landing_surface_child)
		return true
	# Handle landing surface settings
	elif collider is FootstepSurface and collider.footstep_profile:
		_play_landing(collider.footstep_profile)
		return true
	return false

func _play_by_material(collider : Node3D) -> bool:
	# If no landing surface, see if we can get a material
	if landing_material_library:
		# Find surface material
		var material : Material = _get_surface_material(collider)
		# If a material was found
		if material:
			print(material)
			# Get a profile from our library
			var landing_profile = landing_material_library.get_footstep_profile_by_material(material)
			# If a profile is found, use it
			if landing_profile:
				_play_landing(landing_profile)
				return true
	return false

func _get_landing_surface_child(collider : Node3D) -> AudioStreamRandomizer:
	# Find all children of the collider static body that are of type "FootstepSurface"
	var landing_surfaces = collider.find_children("", "FootstepSurface")
	if landing_surfaces:
		# Use the first landing_surface child found
		return landing_surfaces[0].footstep_profile
	return null

func _get_surface_material(collider : Node3D) -> Material:
	# Similar logic as FootstepPlayer to retrieve material from collider
	var mesh_instance = null
	var meshes = []
	if collider is CSGShape3D:
		if collider is CSGCombiner3D:
			# Composite mesh
			if collider.material_override:
				return collider.material_override
			meshes = collider.get_meshes()
		else:
			return collider.material
	elif collider is StaticBody3D or collider is RigidBody3D:
		# Find all children of the collider static body that are of type "MeshInstance3D"
		if collider.get_parent() is MeshInstance3D:
			mesh_instance = collider.get_parent()
		else:
			var mesh_instances = collider.find_children("", "MeshInstance3D")
			if mesh_instances:
				if len(mesh_instances) == 1:
					mesh_instance = mesh_instances[0]
				else:
					meshes = mesh_instances
	
	if meshes:
		# Handle multiple meshes
		mesh_instance = meshes[0]
	
	if mesh_instance and 'mesh' in mesh_instance:
		var mesh = mesh_instance.mesh
		if mesh.get_surface_count() == 0:
			return null
		elif mesh.get_surface_count() == 1:
			return mesh.surface_get_material(0)
		else:
			# Advanced logic for multiple surfaces
			return _find_surface_material_by_face(mesh, mesh_instance)
	return null

func _find_surface_material_by_face(mesh: Mesh, mesh_instance: MeshInstance3D) -> Material:
	# Logic to find the correct material based on the face the player collided with
	var face = null
	var ray = last_result['position'] - global_position
	var faces = mesh.get_faces()
	var aabb = mesh.get_aabb()
	var accuracy = round(4 * aabb.size.length_squared())
	var snap = aabb.size / accuracy
	var coord = null
	
	for i in range(len(faces) / 3):
		var face_idx = i * 3
		var a = mesh_instance.to_global(faces[face_idx])
		var b = mesh_instance.to_global(faces[face_idx+1])
		var c = mesh_instance.to_global(faces[face_idx+2])
		var ray_t = Geometry3D.ray_intersects_triangle(global_position, ray, a, b, c)
		if ray_t:
			face = faces.slice(face_idx, face_idx+3)
			coord = [round(faces[face_idx] / snap), round(faces[face_idx+1] / snap), round(faces[face_idx+2] / snap)]
			break
	
	var mat = null
	if face:
		for surface in range(mesh.get_surface_count()):
			var surf = mesh.surface_get_arrays(surface)[0]
			var has_vert_a = false
			var has_vert_b = false
			var has_vert_c = false
			for vert in surf:
				var vert_coord = round(vert / snap)
				has_vert_a = has_vert_a or vert_coord == coord[0]
				has_vert_b = has_vert_b or vert_coord == coord[1]
				has_vert_c = has_vert_c or vert_coord == coord[2]
				if has_vert_a and has_vert_b and has_vert_c:
					mat = mesh.surface_get_material(surface)
					break
			if has_vert_a and has_vert_b and has_vert_c:
				break
	return mat

func _play_landing(landing_profile : AudioStreamRandomizer):
	stream = landing_profile
	play()
