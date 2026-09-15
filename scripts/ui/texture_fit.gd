class_name TextureFit
extends RefCounted

# TextureRect 하나를 컨테이너 크기에 맞춰 배치하는 공용 계산기. Main.gd의
# 캐릭터 스테이지(1-3)와 캐릭터 편집 화면(1-6)이 "비율 유지 + 위/가운데 기준
# 크롭"이라는 같은 로직이 필요해서 공유 유틸로 뽑았다.


## container_size 안에 texture를 비율 유지한 채 배치한다.
## cover=false: 컨테이너 안에 다 들어오게 축소(contain, 잘리지 않음).
## cover=true: 컨테이너를 꽉 채우고 넘치는 쪽은 잘라낸다(cover, 크롭됨).
## vertical_anchor: 세로 정렬 기준. 0.0=위쪽(얼굴 쪽), 0.5=가운데, 1.0=아래쪽(발이 바닥에).
## 가로 방향은 항상 가운데 정렬한다.
static func fit(rect: TextureRect, texture: Texture2D, container_size: Vector2, cover: bool, vertical_anchor: float) -> void:
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE

	if texture == null or container_size.x <= 0 or container_size.y <= 0:
		return

	var tex_size := texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return

	var scale: float
	if cover:
		scale = max(container_size.x / tex_size.x, container_size.y / tex_size.y)
	else:
		scale = min(container_size.x / tex_size.x, container_size.y / tex_size.y)

	var display_size := tex_size * scale
	rect.size = display_size
	rect.position = Vector2(
		(container_size.x - display_size.x) / 2.0,
		(container_size.y - display_size.y) * vertical_anchor
	)
