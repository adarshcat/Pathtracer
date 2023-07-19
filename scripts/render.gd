extends Control

const sc := 1.0
const maxBounce := 12
const iterations := 1

var dim := Vector2i(500, 500)
var inv := 4

var samples := 1

@onready var mainData := preload("res://scenes/main.tscn")
@onready var outputRect := get_node("output")
@onready var fpsLabel := get_node("fpsLabel")
@export_file var hdrPath:String
@onready var hdr:Image

var hdrData:PackedByteArray

var main:Game

#shader variables
var rd:RenderingDevice
var shaderRID:RID

var materialDataRID:RID
var cameraDataRID:RID
var textureRID:RID
var sphereDataRID:RID
var planeDataRID:RID
var hdrDataRID:RID
var settingsDataRID:RID
var triangleDataRID:RID

var uniformSetRID:RID
var pipelineRID:RID

func _ready() -> void:
	randomize()
	
	#instantiate the main scene
	main = mainData.instantiate()
	main.visible = false
	add_child(main)
	
	#load hdr
	hdr = Image.load_from_file(hdrPath)
	hdrData = getHDRData()
	
	#calculate render resolution based on the scale provided
	dim.x = int(get_viewport_rect().size.x * sc)
	dim.x -= dim.x%inv
	dim.y = int(get_viewport_rect().size.y * sc)
	dim.y -= dim.y%inv
	
	#prepare the compute shader
	prepareShader()
	createIOStream(main.getCameraData(), main.getMaterialData(), main.getSphereData(), main.getPlaneData(), main.getSettingsData(maxBounce, iterations), main.getTriangleData())

func _process(delta:float) -> void:
	updateShaderReq(main.getSettingsData(maxBounce, iterations, samples))
	dispatchShader()
	samples += 1
	fpsLabel.text = "Fps: "+str(int(Engine.get_frames_per_second()))+" , Samples: "+str(samples)


# shader functions--------------

func prepareShader() -> void:
	rd = RenderingServer.create_local_rendering_device()
	var shader_file := load("res://compute/renderer.glsl")
	var shader_spirv:RDShaderSPIRV = shader_file.get_spirv()
	shaderRID = rd.shader_create_from_spirv(shader_spirv)

func createIOStream(cameraDataBytes:PackedByteArray, materialDataBytes:PackedByteArray, sphereDataBytes:PackedByteArray, planeDataBytes:PackedByteArray, settingsDataBytes:PackedByteArray, triangleDataBytes:PackedByteArray) -> void:
	#Preparing an uniform which stores the camera data
	cameraDataRID = rd.storage_buffer_create(cameraDataBytes.size(), cameraDataBytes)
	
	var cameraUniform := RDUniform.new()
	cameraUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cameraUniform.binding = 0
	cameraUniform.add_id(cameraDataRID)
	
	#Preparing an uniform which stores the material data
	materialDataRID = rd.storage_buffer_create(materialDataBytes.size(), materialDataBytes)
	
	var matUniform := RDUniform.new()
	matUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	matUniform.binding = 1
	matUniform.add_id(materialDataRID)
	
	#Preparing the output texture uniform
	var imageFormat := RDTextureFormat.new()
	imageFormat.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	imageFormat.width = dim.x
	imageFormat.height = dim.y
	
	imageFormat.usage_bits = \
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT + \
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + \
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var blankImg := Image.create(dim.x, dim.y, false, Image.FORMAT_RGBA8)
	
	textureRID = rd.texture_create(imageFormat, RDTextureView.new(), [blankImg.get_data()])
	
	var texUniform := RDUniform.new()
	texUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texUniform.binding = 2
	texUniform.add_id(textureRID)
	
	#Passing an uniform which stores sphere objects data
	sphereDataRID = rd.storage_buffer_create(sphereDataBytes.size(), sphereDataBytes)
	
	var spUniform := RDUniform.new()
	spUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	spUniform.binding = 4
	spUniform.add_id(sphereDataRID)
	
	#Passing an uniform which stores plane objects data
	planeDataRID = rd.storage_buffer_create(planeDataBytes.size(), planeDataBytes)
	
	var plUniform := RDUniform.new()
	plUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	plUniform.binding = 3
	plUniform.add_id(planeDataRID)
	
	#Preparing the hdr texture uniform
	var imageFormat2 := RDTextureFormat.new()
	imageFormat2.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_UNORM
	imageFormat2.width = hdr.get_width()
	imageFormat2.height = hdr.get_height()
	
	imageFormat2.usage_bits = \
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT + \
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + \
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	hdrDataRID = rd.texture_create(imageFormat2, RDTextureView.new(), [hdrData])
	
	var hdrUniform := RDUniform.new()
	hdrUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	hdrUniform.binding = 5
	hdrUniform.add_id(hdrDataRID)
	
	#Passing an uniform which stores the settings for the renderer (not exactly 'settings' bruh..)
	settingsDataRID = rd.storage_buffer_create(settingsDataBytes.size(), settingsDataBytes)
	
	var setUniform := RDUniform.new()
	setUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	setUniform.binding = 6
	setUniform.add_id(settingsDataRID)
	
	#Passing an uniform which stores the settings for the renderer (not exactly 'settings' bruh..)
	triangleDataRID = rd.storage_buffer_create(triangleDataBytes.size(), triangleDataBytes)
	
	var triangleUniform := RDUniform.new()
	triangleUniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	triangleUniform.binding = 7
	triangleUniform.add_id(triangleDataRID)
	
	#combining all the uniforms into a uniform set
	uniformSetRID = rd.uniform_set_create([cameraUniform, matUniform, texUniform, plUniform, spUniform, hdrUniform, setUniform, triangleUniform], shaderRID, 0)

func dispatchShader() -> void:
	pipelineRID = rd.compute_pipeline_create(shaderRID)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelineRID)
	rd.compute_list_bind_uniform_set(compute_list, uniformSetRID, 0)
	rd.compute_list_dispatch(compute_list, dim.x/inv, dim.y/inv, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	#retrieving the texture output of the render
	var textureBytes := rd.texture_get_data(textureRID, 0)
	var texture := Image.create_from_data(dim.x, dim.y, false, Image.FORMAT_RGBA8, textureBytes)
	
	outputRect.texture = ImageTexture.create_from_image(texture)

#updates all the buffers including the camera buffer and the ones that store the object data
func updateShader(cameraDataBytes:PackedByteArray, settingsDataBytes:PackedByteArray, sphereDataBytes:PackedByteArray, planeDataBytes:PackedByteArray) -> void:
	rd.buffer_update(settingsDataRID, 0, settingsDataBytes.size(), settingsDataBytes)
	rd.buffer_update(cameraDataRID, 0, cameraDataBytes.size(), cameraDataBytes)
	rd.buffer_update(sphereDataRID, 0, sphereDataBytes.size(), sphereDataBytes)
	rd.buffer_update(planeDataRID, 0, planeDataBytes.size(), planeDataBytes)

#updates only the required buffers
func updateShaderReq(settingsDataBytes:PackedByteArray) -> void:
	rd.buffer_update(settingsDataRID, 0, settingsDataBytes.size(), settingsDataBytes)

#extremely inefficent hdr parser
func getHDRData():
	var data := PackedByteArray()
	data.resize(16777216)
	
#	var off := 0
#	for j in range(hdr.get_height()):
#		for i in range(hdr.get_width()):
#			var col := hdr.get_pixel(i, j)
#			data.encode_u16(off, int(min(col.r, 2.0)*32767.5))
#			off+=2
#			data.encode_u16(off, int(min(col.g, 2.0)*32767.5))
#			off+=2
#			data.encode_u16(off, int(min(col.b, 2.0)*32767.5))
#			off+=2
#			data.encode_u16(off, 65535)
#			off+=2
	return data

#Cleanup -----------

func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		cleanup_gpu()

func cleanup_gpu() -> void:
	if rd == null:
		return
	
	rd.free_rid(pipelineRID)
	pipelineRID = RID()
	
	rd.free_rid(uniformSetRID)
	uniformSetRID = RID()
	
	rd.free_rid(materialDataRID)
	materialDataRID = RID()
	
	rd.free_rid(cameraDataRID)
	cameraDataRID = RID()
	
	rd.free_rid(textureRID)
	textureRID = RID()
	
	rd.free_rid(sphereDataRID)
	sphereDataRID = RID()
	
	rd.free_rid(planeDataRID)
	planeDataRID = RID()
	
	rd.free_rid(hdrDataRID)
	hdrDataRID = RID()
	
	rd.free_rid(settingsDataRID)
	settingsDataRID = RID()
	
	rd.free_rid(triangleDataRID)
	triangleDataRID = RID()
	
	rd.free_rid(shaderRID)
	shaderRID = RID()
	
	rd.free()
	rd = null
