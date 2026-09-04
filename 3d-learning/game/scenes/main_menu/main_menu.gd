extends Node2D

@export var use_steam: bool = false

@onready var host_button: Button = $CanvasLayer/HostButton
@onready var join_button: Button = $CanvasLayer/JoinButton


func _ready() -> void:
	host_button.pressed.connect(func(): MultiplayerService.host_game(use_steam))
	join_button.pressed.connect(func(): MultiplayerService.join_game(use_steam))
