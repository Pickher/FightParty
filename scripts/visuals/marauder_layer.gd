extends "res://scripts/visuals/tracked_projectile_layer.gd"

const Actor = preload("res://scripts/visuals/marauder_actor.gd")
const Ordnance = preload("res://scripts/visuals/marauder_ordnance.gd")
const MODEL_PATH := "res://assets/models/marauder/marauder_rig.glb"
const MODE := "concussive_grenade"

func _init() -> void:
	super("marauder", MODE, "ground", Actor, Ordnance)

func _socket(actor: Node3D, side: int) -> Transform2D:
	var axis: Vector2 = actor.muzzle_heading(side)
	return Transform2D(axis.angle(), actor.muzzle_screen_offset(side))

func _fire_actor(actor: Node3D, offset: Vector2, age: float, side: int) -> void:
	actor.fire_at(offset, age, side)
