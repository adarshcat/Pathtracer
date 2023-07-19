extends Node3D
class_name Game

@onready var camera := get_node("anchor/camera")
@onready var materialCont := get_node("materials")

@onready var sphereCont := get_node("sphereCont")
@onready var planeCont := get_node("planeCont")
@onready var polyCont := get_node("polygons")

#Helper functions below-------

func getSphereData() -> PackedByteArray:
	var dataArr:PackedFloat32Array = []
	for child in sphereCont.get_children():
		if (!child.visible): continue
		dataArr.append(child.global_position.x)
		dataArr.append(child.global_position.y)
		dataArr.append(child.global_position.z)
		dataArr.append(child.mesh.radius*child.scale.x)
		dataArr.append_array(PackedFloat32Array([child.get_meta("mat")-1, 0.0, 0.0, 0.0]))
	
	return dataArr.to_byte_array()

func getPlaneData() -> PackedByteArray:
	var dataArr:PackedFloat32Array = []
	for child in planeCont.get_children():
		if (!child.visible): continue
		dataArr.append(child.position.x)
		dataArr.append(child.position.y)
		dataArr.append(child.position.z)
		dataArr.append(0.0)
		var norm := getPlaneNormal(child)
		dataArr.append(norm.x)
		dataArr.append(norm.y)
		dataArr.append(norm.z)
		dataArr.append(child.get_meta("mat")-1)
	
	return dataArr.to_byte_array()

func getPlaneNormal(plane:MeshInstance3D) -> Vector3:
	var x := plane.rotation.x
	var y := plane.rotation.y
	var z := plane.rotation.z
	var rotMatx := Basis(Vector3(1, 0, 0), Vector3(0, cos(x), sin(x)), Vector3(0, -sin(x), cos(x)))
	var rotMaty := Basis(Vector3(cos(y), 0, -sin(y)), Vector3(0, 1, 0), Vector3(sin(y), 0, cos(y)))
	var rotMatz := Basis(Vector3(cos(z), sin(z), 0), Vector3(-sin(z), cos(z), 0), Vector3(0, 0, 1))
	
	var transX := rotMatx * Vector3(0, 1, 0)
	var transY := rotMaty * transX
	return (rotMatz * transY)

func getTriangleData() -> PackedByteArray:
	var dataArr := PackedFloat32Array()
	
	for child in polyCont.get_children():
		if (!child.visible): continue
		var faces:PackedVector3Array = child.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			faces[i] = child.global_transform*faces[i]
			faces[i+1] = child.global_transform*faces[i+1]
			faces[i+2] = child.global_transform*faces[i+2]
			dataArr.append_array(PackedFloat32Array([faces[i].x, faces[i].y, faces[i].z, 0.0]))
			dataArr.append_array(PackedFloat32Array([faces[i+1].x, faces[i+1].y, faces[i+1].z, 0.0]))
			dataArr.append_array(PackedFloat32Array([faces[i+2].x, faces[i+2].y, faces[i+2].z]))
			
			dataArr.append(child.get_meta("mat")-1)
			
			var triangleNorm:Vector3 = getTriangleNorm(faces[i], faces[i+1], faces[i+2])
			dataArr.append_array(PackedFloat32Array([triangleNorm.x, triangleNorm.y, triangleNorm.z]))
			
			var d := -triangleNorm.dot(faces[i])
			dataArr.append(d)
	
	return dataArr.to_byte_array()

func getTriangleNorm(v0:Vector3, v1:Vector3, v2:Vector3) -> Vector3:
	var s1 := v1-v0
	var s2 := v2-v0
	
	var norm := s1.cross(s2)
	return norm.normalized()

func getMaterialData() -> PackedByteArray:
	var dataArr:PackedFloat32Array = []
	for child in materialCont.get_children():
		dataArr.append(child.albedo.r)
		dataArr.append(child.albedo.g)
		dataArr.append(child.albedo.b)
		dataArr.append_array(PackedFloat32Array([child.roughness, child.emissionStr, child.specularity, 0.0, 0.0]))
	
	return dataArr.to_byte_array()

func getSettingsData(maxBounce:int, iterations:int, samples:int=1) -> PackedByteArray:
	var byteArr := PackedByteArray();
	byteArr.append_array(PackedInt32Array([randi_range(10, 1000000), samples, maxBounce, iterations]).to_byte_array())
	return byteArr;

func getCameraData() -> PackedByteArray:
	var byteArr := matrixToBytes(camera.global_transform)
	byteArr.append_array(getInvProjectionMatrix(camera.fov, camera.far, camera.near))
	byteArr.append_array(PackedFloat32Array([camera.fov, camera.near, camera.far]).to_byte_array())
	return byteArr

func getInvProjectionMatrix(fovDeg:float, farPlane:float, nearPlane:float) -> PackedByteArray:
	var S := 1.0 / tan(deg_to_rad(fovDeg / 2.0))
	var mfbfmn := (-farPlane) / (farPlane - nearPlane)
	var mfinbfmn := -(farPlane * nearPlane) / (farPlane - nearPlane)
	
	var proj:Projection = Projection(
		Vector4(S/(get_viewport().size.aspect()), 0.0, 0.0, 0.0),
		Vector4(0.0, -S, 0.0, 0.0),
		Vector4(0.0, 0.0, mfbfmn, mfinbfmn),
		Vector4(0.0, 0.0, -1.0, 0.0)
	)
	proj = proj.inverse()
	
	var projMat:PackedByteArray = PackedFloat32Array([
		proj.x.x, proj.y.x, proj.z.x, proj.w.x,
		proj.x.y, proj.y.y, proj.z.y, proj.w.y,
		proj.x.z, proj.y.z, proj.z.z, proj.w.z,
		proj.x.w, proj.y.z, proj.z.w, proj.w.w
	]).to_byte_array()
	
	return projMat

func matrixToBytes(t:Transform3D) -> PackedByteArray:
	var basis:Basis = t.basis
	var origin:Vector3 = t.origin
	var bytes:PackedByteArray = PackedFloat32Array([
		basis.x.x, basis.x.y, basis.x.z, 1.0,
		basis.y.x, basis.y.y, basis.y.z, 1.0,
		basis.z.x, basis.z.y, basis.z.z, 1.0,
		origin.x, origin.y, origin.z, 1.0
	]).to_byte_array()
	return bytes
