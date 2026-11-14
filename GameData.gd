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
var _stone_cache := {}
var _tint_shader: Shader


func _ready() -> void:
	randomize()
	_setup_input()
	_load()
	process_mode = Node.PROCESS_MODE_ALWAYS   # sound keeps playing on the pause screen
	_music = AudioStreamPlayer.new()
	_music.volume_db = -12.0
	add_child(_music)
	# Every button in the game clicks, wherever it is made.
	get_tree().node_added.connect(func(n): if n is Button: n.pressed.connect(sfx.bind("click")))


# --- sound -------------------------------------------------------------------

var _sfx := {}   # sound name -> its player
var _music: AudioStreamPlayer


func sfx(sound: String) -> void:
	if not _sfx.has(sound):
		var p := AudioStreamPlayer.new()
		p.stream = load("res://audio/%s.ogg" % sound)
		p.max_polyphony = 4
		add_child(p)
		_sfx[sound] = p
	_sfx[sound].play()


# "menu" or "game"; "" stops the music. Asking for the track already playing does nothing.
func music(track: String) -> void:
	if track == "":
		_music.stop()
		return
	var stream: AudioStreamOggVorbis = load("res://audio/music_%s.ogg" % track)
	if _music.stream == stream and _music.playing:
		return
	stream.loop = true
	_music.stream = stream
	_music.play()


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
	th.set_stylebox("panel", "PanelContainer", stone_box("panel", 8))
	th.set_stylebox("normal", "Button", stone_box("button", 4))
	th.set_stylebox("hover", "Button", stone_box("hover", 4))
	th.set_stylebox("pressed", "Button", stone_box("pressed", 4))
	var focus := box(Color(0, 0, 0, 0), accent.lightened(0.4), 3, 0, 12)
	focus.draw_center = false
	th.set_stylebox("focus", "Button", focus)
	th.set_color("font_color", "Button", p.text)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_focus_color", "Button", Color.WHITE)
	th.set_font_size("font_size", "Button", 16)
	return th


# --- dungeon stone frames ----------------------------------------------------

# A panel or button drawn as a frame of carved stone blocks with a metal stud
# in each corner. The frame is painted pixel by pixel into a tiny 16x16
# picture, blown up 3x, and then tiled along the edges so any size works.
# kind: "panel", "button", "hover" or "pressed". pad: space inside the frame.
func stone_box(kind: String, pad: int) -> StyleBoxTexture:
	var key := biome + kind
	if not _stone_cache.has(key):
		_stone_cache[key] = _stone_texture(kind)
	var sb := StyleBoxTexture.new()
	sb.texture = _stone_cache[key]
	sb.set_texture_margin_all(12)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.set_content_margin_all(12 + pad)
	return sb


func _stone_texture(kind: String) -> ImageTexture:
	var p := pal()
	var wall: Color = p.wall
	var accent: Color = p.accent
	var fill: Color = p.panel
	var stone := wall.lerp(Color(0.42, 0.42, 0.46), 0.6)   # grey stone with a hint of the biome
	var pressed := false
	match kind:
		"button":
			fill = p.panel_hi
		"hover":
			fill = (p.panel_hi as Color).lightened(0.12)
			stone = stone.lightened(0.15)
		"pressed":
			fill = accent.darkened(0.5)
			pressed = true
	var light := stone.lightened(0.35)
	var dark := stone.darkened(0.5)
	if pressed:   # a pressed slab is lit from the other side
		var swap := light
		light = dark
		dark = swap
	var edge := Color(0.05, 0.04, 0.04)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d: int = min(min(x, y), min(15 - x, 15 - y))   # how far in from the edge
			var c := fill
			if d == 0:
				var corner := (x == 0 or x == 15) and (y == 0 or y == 15)
				c = Color(0, 0, 0, 0) if corner else edge
			elif d == 1:
				var top_left := x == 1 or y == 1
				var bottom_right := x == 14 or y == 14
				c = stone if (top_left and bottom_right) else (light if top_left else dark)
			elif d == 2:
				c = stone.darkened(0.12) if (x * 7 + y * 13) % 5 == 0 else stone
			elif d == 3:
				c = edge
			if (d == 1 or d == 2) and (x == 7 or y == 7):
				c = stone.darkened(0.5)   # the gap between two blocks
			img.set_pixel(x, y, c)
	var stud := accent.lerp(Color(0.8, 0.8, 0.8), 0.35)
	for at in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
		img.set_pixel(at.x, at.y, stud)
	img.resize(48, 48, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


# Fills a rectangle with a dim brick wall. `draw_on` is the node being drawn.
func draw_bricks(draw_on: CanvasItem, area: Rect2) -> void:
	var p := pal()
	var base: Color = p.bg
	var mortar := base.darkened(0.45)
	draw_on.draw_rect(area, mortar)
	var row := 0
	var y := area.position.y
	while y < area.end.y:
		var x := area.position.x - (24.0 if row % 2 == 1 else 0.0)
		var col := 0
		while x < area.end.x:
			var shade := 0.05 + 0.03 * float((col * 31 + row * 17) % 4)
			draw_on.draw_rect(Rect2(x, y, 45, 21), base.lightened(shade))
			draw_on.draw_rect(Rect2(x, y, 45, 3), base.lightened(shade + 0.05))
			x += 48.0
			col += 1
		y += 24.0
		row += 1


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
