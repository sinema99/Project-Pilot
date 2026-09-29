extends VBoxContainer

# INVENTORY: a tab that exists so the taxonomy is visible and the layout can be
# judged, with nothing in it yet. Explicitly out of scope in docs/specs/ui-shell.md
# - items need a data model that does not exist.
#
# SETTINGS used to share this script too. It gained real content and its own
# script - see docs/specs/settings.md - which is what happens to any tab that
# stops being empty.

# Nothing here takes focus, so the row-navigation hints would be a lie.
func hints() -> Array:
	return [
		{"key": "ESC", "label": "CLOSE"},
	]
