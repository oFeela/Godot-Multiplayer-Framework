extends Node

## THIS IS THE CONSTANTS YOU WANT TO CHANGE
## FOR THE GAME YOU WANT TO WORK WITH

## THESE ARE ALL USED BY THE FRAMEWORK

enum MultiplayerMode {P2P, CENTRALIZED}
enum LogLevel {DEBUG, INFO, WARN, ERROR, NONE}

const LOG_LEVEL := LogLevel.INFO

const HMAC_SECRET_KEY := "67Miguel67_Change_In_Production_Ok"
const MULTIPLAYER_MODE := MultiplayerMode.P2P
const DEFAULT_PORT := 4242
const DEFAULT_MAX_PLAYERS := 4
const DEFAULT_USE_STEAM := false

const MULTIPLAYER_WORLD_PATH := "uid://e5owhf6b1sn7"
const MAIN_MENU_PATH := "uid://cxy3auj6iey8l"
const INITIAL_REGISTERED_SCENES: Dictionary[String, PackedScene] = {
	"player": preload("uid://bg4uh6g3e6swi")
}

const PLAYER_AUTO_SPAWN := true
const PLAYER_RESPAWN_TIME := 3.0
const DATA_STORE_AUTO_SAVE_TIME := 15.0
