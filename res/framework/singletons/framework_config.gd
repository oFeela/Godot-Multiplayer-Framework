## Global configuration file containing environment settings, network constants, and defaults.
##
## [FrameworkConfig] acts as the single source of truth for core framework settings
## such as network modes, logging levels, scene preloads, and player lifecycle defaults.
extends Node

## Defines the underlying networking architecture for the session.
enum MultiplayerMode {
	P2P, ## Host-as-Server Peer-to-Peer architecture.
	CENTRALIZED ## Dedicated server architecture.
}

## Controls the verbosity of global logging via [LoggerService].
enum LogLevel {
	DEBUG, ## Fine-grained informational events for debugging.
	INFO, ## Normal operational messages.
	WARN, ## Warnings regarding non-fatal runtime issues.
	ERROR, ## Critical failures and error events.
	NONE ## Silences all logger output.
}

## Active log level for [LoggerService]. Messages below this severity are ignored.
const LOG_LEVEL := LogLevel.WARN

## Secret key used for HMAC signature generation and data validation.
## [color=yellow]Warning:[/color] Change this value in production!
const HMAC_SECRET_KEY := "67Miguel67_Change_In_Production_Ok"

## Network topology used by the multiplayer system.
const MULTIPLAYER_MODE := MultiplayerMode.P2P

## Default port used when creating or connecting to a multiplayer server.
const DEFAULT_PORT := 4242

## Maximum allowed concurrent player connections on a hosted server.
const DEFAULT_MAX_PLAYERS := 4

## Toggles whether Steamworks integration should be used for networking.
const DEFAULT_USE_STEAM := false

## UID path to the main multiplayer world/game scene.
const MULTIPLAYER_WORLD_PATH := "uid://e5owhf6b1sn7"

## UID path to the main menu UI scene.
const MAIN_MENU_PATH := "uid://cxy3auj6iey8l"

## Pre-cached registry of core framework scenes mapped to string keys.
const INITIAL_REGISTERED_SCENES: Dictionary[String, PackedScene] = {
	"player": preload("uid://bg4uh6g3e6swi")
}

## Pre-cached registry of core framework audio streams mapped to string keys.
const INITIAL_REGISTERED_SOUNDS: Dictionary[String, AudioStream] = {}

## Controls whether player character instances spawn automatically upon joining.
const PLAYER_AUTO_SPAWN := true

## Respawn delay in seconds after a player character is eliminated.
const PLAYER_RESPAWN_TIME := 3.0

## Interval in seconds between automatic saves by [DataProfileStore].
const DATA_STORE_AUTO_SAVE_TIME := 15.0
