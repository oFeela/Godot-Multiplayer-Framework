extends Node

func debug(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.DEBUG:
		print_rich("[color=gray][DEBUG][/color] %s" % str(message))

func info(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.INFO:
		print_rich("[color=cyan][INFO][/color] %s" % str(message))

func warn(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.WARN:
		push_warning(str(message))
		print_rich("[color=yellow][WARN][/color] %s" % str(message))

func error(message: Variant) -> void:
	if FrameworkConfig.LOG_LEVEL <= FrameworkConfig.LogLevel.ERROR:
		push_error(str(message))
		print_rich("[color=red][BOLD][ERROR][/BOLD][/color] %s" % str(message))
