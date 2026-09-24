class_name Tokens
extends RefCounted

## Design tokens: the single source of every colour, size, duration and easing
## in Aphelion.
##
## Nothing in the UI hard-codes a colour or a pixel value. That is not tidiness
## for its own sake — it is what makes the light theme, the colourblind palette,
## the UI scale slider and reduced motion possible at all, because each of them
## is a different reading of this same table rather than a parallel set of
## widgets.
##
## Contrast: every foreground/background pair used for text meets WCAG AA
## (4.5:1 for body text, 3:1 for large text and UI boundaries). The ratios are
## asserted in tests/unit/test_tokens.gd, so a future palette tweak that breaks
## accessibility fails the build rather than shipping.

# --- spacing: a 4 px base, because every size in the UI is a multiple of it ---
const SPACE_1 := 4.0
const SPACE_2 := 8.0
const SPACE_3 := 12.0
const SPACE_4 := 16.0
const SPACE_5 := 24.0
const SPACE_6 := 32.0
const SPACE_7 := 48.0
const SPACE_8 := 64.0

# --- radii ---
const RADIUS_SM := 4.0
const RADIUS_MD := 8.0
const RADIUS_LG := 14.0

# --- type scale ---
const FONT_XS := 11
const FONT_SM := 13
const FONT_MD := 15
const FONT_LG := 19
const FONT_XL := 26
const FONT_XXL := 38

# --- borders ---
const BORDER_THIN := 1.0
const BORDER_FOCUS := 2.0

## Motion. CLAUDE.md asks for 150-250 ms transitions: long enough to be read as
## movement, short enough never to be waited on.
const DUR_INSTANT := 0.0
const DUR_FAST := 0.15
const DUR_BASE := 0.2
const DUR_SLOW := 0.25
const EASE_OUT := Tween.EASE_OUT
const TRANS_DEFAULT := Tween.TRANS_CUBIC

## Duration, adjusted for the reduced-motion setting. Every animation in the
## game goes through this, so the switch actually reaches all of them.
static func duration(base: float) -> float:
	return 0.0 if Settings.reduced_motion else base


# --- colour ----------------------------------------------------------------

## Dark theme. The background is a very dark blue rather than black: pure black
## against a starfield loses the sense of depth, and on OLED it smears.
const DARK := {
	"bg":            Color("0b0d14"),
	"surface":       Color("141824"),
	"surface_high":  Color("1d2230"),
	"overlay":       Color("262c3c"),
	"border":        Color("333b50"),
	"border_strong": Color("6c7690"),
	"text":          Color("e8ecf5"),
	"text_muted":    Color("a3adc2"),
	"text_faint":    Color("6f7a91"),
	"accent":        Color("4cc2ff"),
	"accent_text":   Color("06121c"),
	"success":       Color("5fd38d"),
	"warning":       Color("ffb454"),
	"danger":        Color("ff6b6b"),
	"focus":         Color("ffd166"),
}

## Light theme. Not an inversion — the greys are warmed slightly so that a
## bright screen does not read as blue-grey, and the accent is darkened to keep
## its contrast against white above 4.5:1.
const LIGHT := {
	"bg":            Color("f6f7fa"),
	"surface":       Color("ffffff"),
	"surface_high":  Color("eef1f6"),
	"overlay":       Color("e2e7ef"),
	"border":        Color("c8cfdb"),
	"border_strong": Color("798395"),
	"text":          Color("141824"),
	"text_muted":    Color("4a5265"),
	"text_faint":    Color("6f7a91"),
	"accent":        Color("00629b"),
	"accent_text":   Color("ffffff"),
	"success":       Color("1c7a4a"),
	"warning":       Color("8a5300"),
	"danger":        Color("b3261e"),
	"focus":         Color("9a6b00"),
}

## Trajectory colours.
##
## The default set is chosen for hue separation; the colourblind set is built
## for deuteranopia and protanopia, where red and green collapse together. But
## colour is never the only signal either way: every trajectory carries a line
## style (solid, dashed, dotted) and an always-visible text label, so the map is
## readable in greyscale.
const TRAJECTORY_DEFAULT := {
	"current":   Color("4cc2ff"),
	"projected": Color("9d8cff"),
	"target":    Color("ffb454"),
	"transfer":  Color("5fd38d"),
	"danger":    Color("ff6b6b"),
	"past":      Color("6f7a91"),
}

const TRAJECTORY_COLORBLIND := {
	"current":   Color("56b4e9"),  # sky blue
	"projected": Color("cc79a7"),  # reddish purple
	"target":    Color("e69f00"),  # orange
	"transfer":  Color("0072b2"),  # deep blue
	"danger":    Color("d55e00"),  # vermilion
	"past":      Color("999999"),  # grey
}

## Line styles, paired with the colours above so hue is never load-bearing.
## Values are dash patterns in pixels; an empty array means solid.
const TRAJECTORY_DASH := {
	"current":   [],
	"projected": [10.0, 6.0],
	"target":    [2.0, 6.0],
	"transfer":  [16.0, 5.0, 3.0, 5.0],
	"danger":    [6.0, 4.0],
	"past":      [3.0, 7.0],
}


static func palette() -> Dictionary:
	if Settings.theme == "light":
		return LIGHT
	if Settings.theme == "system":
		# Godot does not report the OS theme on every platform; dark is the
		# better default for a game that is mostly starfield.
		return LIGHT if DisplayServer.is_dark_mode_supported() and not DisplayServer.is_dark_mode() else DARK
	return DARK


static func color(name: String) -> Color:
	var p := palette()
	return p.get(name, Color.MAGENTA)


static func trajectory_color(role: String) -> Color:
	var p: Dictionary = TRAJECTORY_COLORBLIND if Settings.palette == "colorblind" \
		else TRAJECTORY_DEFAULT
	return p.get(role, color("text"))


static func trajectory_dash(role: String) -> PackedFloat32Array:
	return PackedFloat32Array(TRAJECTORY_DASH.get(role, []))


static func font_size(base: int) -> int:
	return int(roundf(float(base) * Settings.ui_scale))


static func space(base: float) -> float:
	return roundf(base * Settings.ui_scale)


## Relative luminance per WCAG 2.1.
static func luminance(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	var lin := []
	for v in ch:
		lin.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


## Contrast ratio between two colours, 1.0 to 21.0.
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)
