import iso_prop_patch

_TSCN = """[gd_scene load_steps=5 format=3 uid="uid://test"]

[ext_resource type="PackedScene" uid="uid://muzha_prop_template" path="res://src/maps/props/PropTemplate.tscn" id="4_tmpl"]
[ext_resource type="Texture2D" uid="uid://x" path="res://assets/textures/props/foo.png" id="3_tex"]

[sub_resource type="RectangleShape2D" id="1_rect"]
size = Vector2(16, 16)

[sub_resource type="RectangleShape2D" id="2_irect"]
size = Vector2(48, 16)

[node name="foo" instance=ExtResource("4_tmpl")]
iso_sort_offset = 0.0
[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_tex")
offset = Vector2(0, -24)

[node name="CollisionShape2D" parent="StaticBody2D" index="0"]
position = Vector2(0, -8)
shape = SubResource("1_rect")

[node name="CollisionShape2D" parent="InteractArea" index="0"]
position = Vector2(0, -8)
shape = SubResource("2_irect")
"""


def test_patch_rebakes_sprite_offset_and_diamond():
    out = iso_prop_patch.patch_tscn(
        _TSCN,
        iso_sort_offset=11.0,
        collision_points=[(0.0, 11.0), (23.0, 0.0), (0.0, -11.0), (-24.0, 0.0)],
        tex_h=48,
    )
    # root 寫對 iso_sort_offset
    assert "iso_sort_offset = 11.0" in out
    # Sprite offset 重烘 = -h/2 + iso = -24 + 11 = -13.0  ← 修峰置 bug 的核心
    assert "offset = Vector2(0, -13.0)" in out
    assert "offset = Vector2(0, -24)" not in out
    # body 碰撞換成菱形
    assert "ConvexPolygonShape2D" in out
    assert "points = PackedVector2Array(0.0, 11.0, 23.0, 0.0, 0.0, -11.0, -24.0, 0.0)" in out
    # StaticBody CollisionShape2D 不再有 position
    sb = out[out.index('parent="StaticBody2D"'):]
    sb = sb[: sb.index("[node", 1)]
    assert "position" not in sb
    # InteractArea 仍是矩形且保留 position
    assert 'id="2_irect"' in out
