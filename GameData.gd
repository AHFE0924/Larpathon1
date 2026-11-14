extends Node
# Shared game state, colours, input setup and UI theme. Loaded as an autoload.

const SAVE_PATH := "user://bb_save.cfg"
const START_HP := 3
const HP_CAP := 5

var biome: String = "fire"
var level: int = 1
var total_score: int = 0
var hp: int = START_HP
var max_hp: int = START_HP
var best_score: int = 0
var best_level: int = 0

var PALETTES := {
	"fire": {
		"name": "FIRE",
		"bg": Color("140808"), "floor_a": Color("3b211d"), "floor_b": Color("341c19"),
		"wall": Color("7a4332"), "wall_top": Color("a05a3f"), "wall_dark": Color("2e1611"),
		"accent": Color("ff8a3d"), "hazard": Color("ff6a1f"), "pit": Color("260a05"),
		"panel": Color("241210"), "panel_hi": Color("4a231a"), "text": Color("ffe9d6"),
		"hero": "res://fire-removebg-preview.png", "slime": "res://slimec.png",
		"goblin": "res://goblin_cyan.webp",
	},
	"ice": {
		"name": "ICE",
		"bg": Color("060f1a"), "floor_a": Color("1d3348"), "floor_b": Color("192c40"),
		"wall": Color("3f729a"), "wall_top": Color("62a3cf"), "wall_dark": Color("12283b"),
		"accent": Color("5cd6ff"), "hazard": Color("8af0ff"), "pit": Color("04121f"),
		"panel": Color("0d1c2c"), "panel_hi": Color("1c3d5c"), "text": Color("e2f4ff"),
		"hero": "res://cold-removebg-preview.png", "slime": "res://slime-removebg-preview (1).png",
		"goblin": "res://goblin_red.png",
	},
}

var POWER_COLORS := {
	"heart": Color("ff5a6e"), "shield": Color("7d95ff"), "haste": Color("ffd23f"),
	"freeze": Color("aef0ff"), "fury": Color("c77dff"),
}
var POWER_NAMES := {
	"heart": "+1 HEART", "shield": "SHIELD", "haste": "HASTE", "freeze": "FREEZE", "fury": "FURY",
}

var _used_cache := {}
var _art_cache := {}
var _tint_shader: Shader


func _ready() -> void:
	randomize()
	_setup_input()
	_load()


func pal() -> Dictionary:
	return PALETTES.get(biome, PALETTES["fire"])


func new_run() -> void:
	level = 1
	total_score = 0
	max_hp = START_HP
	hp = START_HP


func record() -> void:
	if total_score > best_score or level > best_level:
		best_score = max(best_score, total_score)
		best_level = max(best_level, level)
		var cfg := ConfigFile.new()
		cfg.set_value("best", "score", best_score)
		cfg.set_value("best", "level", best_level)
		cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = int(cfg.get_value("best", "score", 0))
		best_level = int(cfg.get_value("best", "level", 0))


# --- input -------------------------------------------------------------------

func _setup_input() -> void:
	_action("move_up", [KEY_W, KEY_UP])
	_action("move_down", [KEY_S, KEY_DOWN])
	_action("move_left", [KEY_A, KEY_LEFT])
	_action("move_right", [KEY_D, KEY_RIGHT])
	_action("attack", [KEY_J, KEY_X])
	_action("tether", [KEY_SPACE])
	_action("pause", [KEY_ESCAPE, KEY_P])


func _action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# --- art helpers -------------------------------------------------------------

# Loads a picture. Some of the art (slimec.png) has a solid white background
# instead of a transparent one, so that background is cut away here.
func art(path: String) -> Texture2D:
	if _art_cache.has(path):
		return _art_cache[path]
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_pixel(0, 0).a > 0.5:
			_cut_background(img)
			tex = ImageTexture.create_from_image(img)
	_art_cache[path] = tex
	return tex


# Makes the background colour transparent, working inwards from the edges so
# same-coloured details inside the drawing are kept.
func _cut_background(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bg := img.get_pixel(0, 0)
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or seen[p.y * w + p.x] == 1:
			continue
		seen[p.y * w + p.x] = 1
		var c := img.get_pixel(p.x, p.y)
		if abs(c.r - bg.r) + abs(c.g - bg.g) + abs(c.b - bg.b) > 0.2:
			continue
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		stack.append(p + Vector2i.RIGHT)
		stack.append(p + Vector2i.LEFT)
		stack.append(p + Vector2i.DOWN)
		stack.append(p + Vector2i.UP)

# The sprite sheets have a lot of empty space around the character. This crops
# the sprite to the drawn part, scales it to target_h pixels tall and puts its
# feet foot_y pixels below the centre of the tile.
func fit_sprite(sprite: Sprite2D, tex: Texture2D, target_h: float, foot_y: float) -> void:
	var used := used_rect(tex)
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(used)
	sprite.centered = true
	sprite.rotation = 0.0
	var s: float = target_h / max(1.0, float(used.size.y))
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(0.0, foot_y - target_h * 0.5)


func used_rect(tex: Texture2D) -> Rect2i:
	if _used_cache.has(tex):
		return _used_cache[tex]
	var used := Rect2i(Vector2i.ZERO, Vector2i(tex.get_size()))
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0:
			used = r
	_used_cache[tex] = used
	return used


# Recolours a sprite to one colour while keeping its light and dark areas.
func tint_material(color: Color) -> ShaderMaterial:
	if _tint_shader == null:
		_tint_shader = Shader.new()
		_tint_shader.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = max(c.r, max(c.g, c.b));
	COLOR = vec4(tint.rgb * (0.35 + l * 0.9), c.a);
}"""
	var m := ShaderMaterial.new()
	m.shader = _tint_shader
	m.set_shader_parameter("tint", color)
	return m


func heart_points(size: float, at: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		var x := 16.0 * pow(sin(a), 3)
		var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
		pts.append(at + Vector2(x, y - 2.5) * size / 32.0)
	return pts


# --- UI theme ----------------------------------------------------------------

func box(bg: Color, border: Color, border_w: int, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


func make_theme() -> Theme:
	var p := pal()
	var accent: Color = p.accent
	var th := Theme.new()
	th.default_font = pixel_font()
	th.default_font_size = 16
	th.set_color("font_color", "Label", p.text)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	th.set_constant("shadow_offset_x", "Label", 2)
	th.set_constant("shadow_offset_y", "Label", 2)
	th.set_constant("line_spacing", "Label", 6)
	th.set_stylebox("panel", "PanelContainer", box(Color(p.panel, 0.96), accent.darkened(0.25), 3, 0, 14))
	th.set_stylebox("normal", "Button", box(p.panel_hi, accent.darkened(0.3), 3, 0, 12))
	th.set_stylebox("hover", "Button", box(p.panel_hi.lightened(0.12), accent, 3, 0, 12))
	th.set_stylebox("pressed", "Button", box(accent.darkened(0.35), accent.lightened(0.35), 3, 0, 12))
	var focus := box(Color(0, 0, 0, 0), Color.WHITE, 3, 0, 12)
	focus.draw_center = false
	th.set_stylebox("focus", "Button", focus)
	th.set_color("font_color", "Button", p.text)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_focus_color", "Button", Color.WHITE)
	th.set_font_size("font_size", "Button", 16)
	return th


# --- pixel font --------------------------------------------------------------

# A hand-drawn 5x7 pixel font, built here at start-up so the text matches the
# pixel art. Each glyph is 7 rows of 5 pixels ('#' = on). Lowercase letters
# use the same shapes as capitals. Use sizes that are multiples of 8.
const GLYPHS := {
	" ": "...../...../...../...../...../...../.....",
	"A": ".###./#...#/#...#/#####/#...#/#...#/#...#",
	"B": "####./#...#/#...#/####./#...#/#...#/####.",
	"C": ".###./#...#/#..../#..../#..../#...#/.###.",
	"D": "####./#...#/#...#/#...#/#...#/#...#/####.",
	"E": "#####/#..../#..../####./#..../#..../#####",
	"F": "#####/#..../#..../####./#..../#..../#....",
	"G": ".###./#...#/#..../#.###/#...#/#...#/.###.",
	"H": "#...#/#...#/#...#/#####/#...#/#...#/#...#",
	"I": ".###./..#../..#../..#../..#../..#../.###.",
	"J": "..###/...#./...#./...#./...#./#..#./.##..",
	"K": "#...#/#..#./#.#../##.../#.#../#..#./#...#",
	"L": "#..../#..../#..../#..../#..../#..../#####",
	"M": "#...#/##.##/#.#.#/#.#.#/#...#/#...#/#...#",
	"N": "#...#/##..#/#.#.#/#..##/#...#/#...#/#...#",
	"O": ".###./#...#/#...#/#...#/#...#/#...#/.###.",
	"P": "####./#...#/#...#/####./#..../#..../#....",
	"Q": ".###./#...#/#...#/#...#/#.#.#/#..#./.##.#",
	"R": "####./#...#/#...#/####./#.#../#..#./#...#",
	"S": ".####/#..../#..../.###./....#/....#/####.",
	"T": "#####/..#../..#../..#../..#../..#../..#..",
	"U": "#...#/#...#/#...#/#...#/#...#/#...#/.###.",
	"V": "#...#/#...#/#...#/#...#/#...#/.#.#./..#..",
	"W": "#...#/#...#/#...#/#.#.#/#.#.#/##.##/#...#",
	"X": "#...#/#...#/.#.#./..#../.#.#./#...#/#...#",
	"Y": "#...#/#...#/.#.#./..#../..#../..#../..#..",
	"Z": "#####/....#/...#./..#../.#.../#..../#####",
	"0": ".###./#...#/#..##/#.#.#/##..#/#...#/.###.",
	"1": "..#../.##../..#../..#../..#../..#../.###.",
	"2": ".###./#...#/....#/...#./..#../.#.../#####",
	"3": "####./....#/....#/.###./....#/....#/####.",
	"4": "...#./..##./.#.#./#..#./#####/...#./...#.",
	"5": "#####/#..../####./....#/....#/#...#/.###.",
	"6": ".###./#..../#..../####./#...#/#...#/.###.",
	"7": "#####/....#/...#./..#../..#../..#../..#..",
	"8": ".###./#...#/#...#/.###./#...#/#...#/.###.",
	"9": ".###./#...#/#...#/.####/....#/....#/.###.",
	".": "...../...../...../...../...../.##../.##..",
	",": "...../...../...../...../..#../..#../.#...",
	"!": "..#../..#../..#../..#../..#../...../..#..",
	"?": ".###./#...#/....#/...#./..#../...../..#..",
	":": "...../.##../.##../...../.##../.##../.....",
	"-": "...../...../...../.###./...../...../.....",
	"+": "...../..#../..#../#####/..#../..#../.....",
	"/": "....#/....#/...#./..#../.#.../#..../#....",
	"'": "..#../..#../...../...../...../...../.....",
	"%": "##..#/##.#./...#./..#../.#.../.#.##/#..##",
	"(": "...#./..#../.#.../.#.../.#.../..#../...#.",
	")": ".#.../..#../...#./...#./...#./..#../.#...",
	"·": "...../...../.##../.##../...../...../.....",
}

var _pixel_font: FontFile


func pixel_font() -> FontFile:
	if _pixel_font != null:
		return _pixel_font
	var keys := GLYPHS.keys()
	var img := Image.create(keys.size() * 6, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var f := FontFile.new()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.fixed_size = 8
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	var size := Vector2i(8, 0)
	f.set_cache_ascent(0, 8, 7.0)
	f.set_cache_descent(0, 8, 2.0)
	for i in keys.size():
		var ch: String = keys[i]
		var rows: PackedStringArray = GLYPHS[ch].split("/")
		for y in 7:
			for x in 5:
				if rows[y][x] == "#":
					img.set_pixel(i * 6 + x, y, Color.WHITE)
	f.set_texture_image(0, size, 0, img)
	for i in keys.size():
		var ch: String = keys[i]
		var codes: Array = [ch.unicode_at(0)]
		if ch.to_lower() != ch:
			codes.append(ch.to_lower().unicode_at(0))
		for code in codes:
			f.set_glyph_advance(0, 8, code, Vector2(4 if ch == " " else 6, 0))
			f.set_glyph_offset(0, size, code, Vector2(0, -7))
			f.set_glyph_size(0, size, code, Vector2(5, 7))
			f.set_glyph_uv_rect(0, size, code, Rect2(i * 6, 0, 5, 7))
			f.set_glyph_texture_idx(0, size, code, 0)
	var fallback: Array[Font] = [ThemeDB.fallback_font]   # for characters not drawn above
	f.fallbacks = fallback
	_pixel_font = f
	return f
