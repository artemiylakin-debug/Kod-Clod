class_name PlayerModel
extends RefCounted
## Модель игрока для вида от третьего лица (F5): двуногая модель мобов со своей «кожей»
## (каштановые волосы, бирюзовая футболка, синие штаны). Анимация: шаг, наклон головы, взмах рукой.

var model: MobModel
var _phase := 0.0
var _amount := 0.0
var _last := Vector3.ZERO

static var _skin: Texture2D


static func skin() -> Texture2D:
	if _skin != null:
		return _skin
	var img := MobSkins._img(64, 32)
	var face := Color(0.78, 0.58, 0.44)
	var hair := Color(0.27, 0.17, 0.09)
	var shirt := Color(0.0, 0.66, 0.68)
	var pants := Color(0.2, 0.22, 0.62)
	var shoes := Color(0.35, 0.35, 0.38)
	# Голова: кожа, волосы сверху, сзади и по краям.
	MobSkins._box(img, 0, 0, 8, 8, 8, face, 0.04)
	MobSkins._rect(img, 8, 0, 8, 8, hair, 0.08)
	MobSkins._rect(img, 0, 8, 32, 2, hair, 0.08)
	MobSkins._rect(img, 24, 8, 8, 8, hair, 0.08)
	MobSkins._pattern(img, 8, 8, ["hhhhhhhh", "h......h", "", ".WB..BW.", "...nn...", "..mmmm..", "..m..m.."],
		{"h": hair, "W": Color(0.95, 0.95, 0.95), "B": Color(0.25, 0.25, 0.65), "n": Color(0.55, 0.35, 0.25),
		"m": Color(0.42, 0.25, 0.15)})
	# Туловище, руки (кожа с рукавами), ноги (штаны и обувь).
	MobSkins._box(img, 16, 16, 8, 12, 4, shirt, 0.06)
	MobSkins._box(img, 40, 16, 4, 12, 4, face, 0.04)
	MobSkins._rect(img, 40, 20, 16, 4, shirt, 0.06)
	MobSkins._rect(img, 44, 16, 4, 4, shirt, 0.06)
	MobSkins._box(img, 0, 16, 4, 12, 4, pants, 0.06)
	MobSkins._rect(img, 0, 29, 16, 3, shoes, 0.06)
	_skin = ImageTexture.create_from_image(img)
	return _skin


func create(parent: Node3D) -> void:
	model = MobModel.create("biped", [skin()])
	# Модели существ смотрят в +Z, игрок — в −Z.
	model.root.rotation.y = PI
	model.root.visible = false
	parent.add_child(model.root)


## Каждый кадр: видимость, шаг, голова, рука.
func update(player: Player, delta: float, visible: bool) -> void:
	if model == null:
		return
	model.root.visible = visible
	if not visible:
		_last = player.position
		return
	var moved := Vector2(player.position.x - _last.x, player.position.z - _last.z).length()
	_last = player.position
	var target := clampf(moved / maxf(delta, 0.001) / 4.3, 0.0, 1.0)
	_amount = lerpf(_amount, target, 1.0 - exp(-10.0 * delta))
	_phase += delta * 9.0 * _amount
	var c := sin(_phase)
	model.rot("head", Vector3(-player.pitch, 0, 0))
	model.rot("rleg", Vector3(c * 1.0 * _amount, 0, 0))
	model.rot("lleg", Vector3(-c * 1.0 * _amount, 0, 0))
	var swing := float(player.get("_swing"))
	model.rot("rarm", Vector3(-c * 0.9 * _amount - swing * 1.4, 0, 0))
	model.rot("larm", Vector3(c * 0.9 * _amount, 0, 0))
	if player.sneaking:
		model.rot("body", Vector3(0.4, 0, 0))
	else:
		model.rot("body", Vector3.ZERO)
	var cell := Vector3i(floori(player.position.x), floori(player.position.y + 1.0), floori(player.position.z))
	model.set_light(player.world.get_sky_light(cell) / 15.0,
		ChunkMesher.block_curve[clampi(player.world.get_block_light(cell), 0, 15)], 0.0)
