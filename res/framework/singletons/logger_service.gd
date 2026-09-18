## Centralized rich console logging and diagnostics utility.
##
## [LoggerService] wraps Godot's console printing and error reporting functions
## to provide color-coded, level-filtered output controlled by [FrameworkConfig].
extends Node

## PUBLICS

## Prints a debug-level log message formatted in gray text.
## Filters out if [code]FrameworkConfig.LOG_LEVEL[/code] is higher than [code]DEBUG[/code].
## [param message]: The value or string to log.
func debug(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.DEBUG:
		print_rich("[color=gray][DEBUG][/color] %s" % str(message))

## Prints an info-level log message formatted in cyan text.
## Filters out if [code]FrameworkConfig.LOG_LEVEL[/code] is higher than [code]INFO[/code].
## [param message]: The value or string to log.
func info(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.INFO:
		print_rich("[color=cyan][INFO][/color] %s" % str(message))

## Logs a warning message formatted in yellow text and triggers [method @GlobalScope.push_warning].
## Filters out if [code]FrameworkConfig.LOG_LEVEL[/code] is higher than [code]WARN[/code].
## [param message]: The value or string to log.
func warn(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.WARN:
		push_warning(str(message))
		print_rich("[color=yellow][WARN][/color] %s" % str(message))

## Logs a critical error message formatted in bold red text and triggers [method @GlobalScope.push_error].
## Filters out if [code]FrameworkConfig.LOG_LEVEL[/code] is higher than [code]ERROR[/code].
## [param message]: The value or string to log.
func error(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.ERROR:
		push_error(str(message))
		print_rich("[color=red][BOLD][ERROR][/BOLD][/color] %s" % str(message))
