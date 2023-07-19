extends Node

@export_color_no_alpha var albedo = Color(1.0, 1.0, 1.0);
@export_range (0, 1) var roughness:float = 1.0;
@export_range (0, 1) var specularity:float = 0.0;
@export var emissionStr:float = 0.0;
