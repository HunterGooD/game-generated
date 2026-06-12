extends GutTest

# Blob shadows + soft lights: attachment, geometry, idempotency, additive light.


func _host() -> Node2D:
	var n := Node2D.new()
	add_child_autofree(n)
	return n


func test_blob_shadow_attaches_behind_host() -> void:
	var host := _host()
	var s: BlobShadow = BlobShadow.attach(host, 40.0, 16.0, 3.0)
	assert_not_null(s)
	assert_true(s is Sprite2D, "shadow is a Sprite2D")
	assert_eq(host.get_child(0), s, "shadow is first child (drawn first)")
	assert_eq(s.z_index, -1, "renders behind siblings")
	assert_true(s.show_behind_parent)
	assert_eq(s.light_mask, 0, "never lit by 2D lights")
	assert_eq(s.position, Vector2(0, 3.0))
	# Scale maps the requested px size onto the shared texture.
	assert_almost_eq(s.scale.x, 40.0 / float(BlobShadow.TEX_SIZE), 0.001)
	assert_almost_eq(s.scale.y, 16.0 / float(BlobShadow.TEX_SIZE), 0.001)


func test_blob_shadow_default_height_is_flat() -> void:
	var s: BlobShadow = BlobShadow.attach(_host(), 50.0)
	# height defaults to 0.42×width → a flattened ellipse, never a circle.
	assert_almost_eq(s.scale.y / s.scale.x, 0.42, 0.001)


func test_blob_shadow_is_idempotent() -> void:
	var host := _host()
	var a: BlobShadow = BlobShadow.attach(host, 40.0, 16.0)
	var b: BlobShadow = BlobShadow.attach(host, 60.0, 20.0, 5.0)
	assert_eq(a, b, "second attach reuses the same shadow — never stacks")
	var shadows: int = 0
	for c in host.get_children():
		if c is BlobShadow:
			shadows += 1
	assert_eq(shadows, 1, "exactly one shadow on the host")
	# The reuse re-sizes / re-positions to the latest request.
	assert_almost_eq(b.scale.x, 60.0 / float(BlobShadow.TEX_SIZE), 0.001)
	assert_eq(b.position, Vector2(0, 5.0))


func test_blob_shadow_null_host_safe() -> void:
	assert_null(BlobShadow.attach(null, 40.0))


func test_soft_light_is_additive_glow() -> void:
	var host := _host()
	var l: SoftLight = SoftLight.attach(host, Color(1.0, 0.6, 0.2), 100.0, 0.8, -20.0)
	assert_not_null(l)
	assert_true(l is PointLight2D)
	assert_eq(l.blend_mode, Light2D.BLEND_MODE_ADD, "additive — only brightens")
	assert_almost_eq(l.energy, 0.8, 0.001)
	assert_eq(l.position, Vector2(0, -20.0))
	assert_not_null(l.texture, "needs a texture to render")
	# texture_scale maps the requested lit radius onto the shared texture.
	assert_almost_eq(l.texture_scale, 200.0 / float(SoftLight.TEX_SIZE), 0.001)


func test_soft_light_null_host_safe() -> void:
	assert_null(SoftLight.attach(null, Color.WHITE, 100.0))


func test_blob_shadow_at_feet_drops_to_sprite_bottom() -> void:
	var host := _host()
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(Image.create(100, 100, false, Image.FORMAT_RGBA8))
	spr.centered = true
	spr.position = Vector2(0, -10)
	spr.scale = Vector2(0.5, 0.5)
	host.add_child(spr)
	var s: BlobShadow = BlobShadow.attach_at_feet(host, spr, 40.0, 16.0)
	# feet = pos.y(-10) + halfH(50)·scale(0.5)·padding(0.92) = -10 + 23 = 13
	assert_almost_eq(s.position.y, 13.0, 0.01, "shadow sits at the sprite's base, not the origin")


func test_blob_shadow_at_feet_no_texture_falls_back() -> void:
	var host := _host()
	var spr := Sprite2D.new()
	spr.position = Vector2(0, -7)
	host.add_child(spr)
	var s: BlobShadow = BlobShadow.attach_at_feet(host, spr, 40.0)
	assert_eq(s.position.y, -7.0, "no texture → fall back to the sprite's own y")


func test_soft_light_at_world_pos() -> void:
	var parent := _host()
	var l: SoftLight = SoftLight.at(parent, Vector2(120, -40), Color(1, 0.8, 0.4), 200.0, 0.6)
	assert_not_null(l)
	assert_eq(l.position, Vector2(120, -40))
	assert_eq(l.blend_mode, Light2D.BLEND_MODE_ADD)
	assert_almost_eq(l.energy, 0.6, 0.001)
	assert_null(SoftLight.at(null, Vector2.ZERO, Color.WHITE, 100.0))
