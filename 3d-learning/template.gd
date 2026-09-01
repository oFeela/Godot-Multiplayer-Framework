class_name Template
extends Node
## Documentation comments here
## Add _ in front for PRIVATES
## Two spaces gap between functions
## To children, call methods directly to communicate. To parents, use signals

## CONSTANTS
signal template_signals

enum template_enums {}

const TEMPLATE_CONSTS = null

## VARIABLES
static var static_variables = null

@export var export_variables = null

var regular_variables = null

@onready var onready_variables = null

## STATICS
static func _static_init():
	pass
	
static func static_methods():
	pass
	
## BUILT-IN VIRTUAL METHODS
func _ready() -> void:
	pass
	
func _process(delta: float) -> void:
	pass
	
## OVERRIDEN METHODS (INHERITANCE)
func overriden_methods():
	pass
	
## PUBLICS (PUBLIC API FOR OTHER SCRIPTS)
func public_method():
	pass

## PRIVATES
func _private_method():
	pass
