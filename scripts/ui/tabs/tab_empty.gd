extends VBoxContainer

# Shared by INVENTORY and SETTINGS: a tab that exists so the taxonomy is visible
# and the layout can be judged, with nothing in it yet. Both are explicitly out
# of scope in docs/specs/ui-shell.md - items need a data model, settings need
# persistence, and neither exists.
#
# When one of these gains real content it gets its own script and stops using
# this one.

# Nothing here takes focus, so the row-navigation hints would be a lie.
func hints() -> Array:
	return [
		{"key": "Q/E", "label": "TAB"},
		{"key": "ESC", "label": "CLOSE"},
	]
