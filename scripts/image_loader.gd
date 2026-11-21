class_name ImageLoader
extends RefCounted
## Loads an image file and applies its EXIF orientation (phone photos are often stored rotated).


static func load_image(path: String) -> Image:
	var image := Image.load_from_file(path)
	if (image == null or image.is_empty()) and OS.get_name() == "macOS":
		return _load_with_sips(path)
	if image == null or image.is_empty():
		return null
	var extension := path.get_extension().to_lower()
	if extension == "jpg" or extension == "jpeg":
		_apply_orientation(image, _exif_orientation(path))
	return image


static func _apply_orientation(image: Image, orientation: int) -> void:
	match orientation:
		2: image.flip_x()
		3: image.rotate_180()
		4: image.flip_y()
		5:
			image.flip_x()
			image.rotate_90(COUNTERCLOCKWISE)
		6: image.rotate_90(CLOCKWISE)
		7:
			image.flip_x()
			image.rotate_90(CLOCKWISE)
		8: image.rotate_90(COUNTERCLOCKWISE)


## Returns the EXIF orientation tag (1-8), or 1 if there is none.
static func _exif_orientation(path: String) -> int:
	var bytes := FileAccess.get_file_as_bytes(path)
	var size := bytes.size()
	if size < 12 or bytes[0] != 0xFF or bytes[1] != 0xD8:
		return 1
	var i := 2
	while i + 4 < size and bytes[i] == 0xFF:
		var marker := bytes[i + 1]
		if marker == 0xDA:
			break
		var length := (bytes[i + 2] << 8) | bytes[i + 3]
		if marker == 0xE1 and i + 10 < size and bytes.slice(i + 4, i + 10).get_string_from_ascii().begins_with("Exif"):
			return _tiff_orientation(bytes, i + 10)
		i += 2 + length
	return 1


static func _tiff_orientation(bytes: PackedByteArray, tiff: int) -> int:
	if tiff + 8 > bytes.size():
		return 1
	var little := bytes[tiff] == 0x49
	var ifd := tiff + _read32(bytes, tiff + 4, little)
	if ifd + 2 > bytes.size():
		return 1
	var entries := _read16(bytes, ifd, little)
	for e in entries:
		var entry := ifd + 2 + 12 * e
		if entry + 12 > bytes.size():
			break
		if _read16(bytes, entry, little) == 0x0112:
			var value := _read16(bytes, entry + 8, little)
			return value if value >= 1 and value <= 8 else 1
	return 1


static func _read16(bytes: PackedByteArray, offset: int, little: bool) -> int:
	if little:
		return bytes[offset] | (bytes[offset + 1] << 8)
	return (bytes[offset] << 8) | bytes[offset + 1]


static func _read32(bytes: PackedByteArray, offset: int, little: bool) -> int:
	if little:
		return _read16(bytes, offset, true) | (_read16(bytes, offset + 2, true) << 16)
	return (_read16(bytes, offset, false) << 16) | _read16(bytes, offset + 2, false)


## Godot cannot read HEIC and some other formats; macOS can convert them with the built-in sips tool.
static func _load_with_sips(path: String) -> Image:
	var temp := OS.get_user_data_dir().path_join("converted.jpg")
	var output: Array = []
	DirAccess.remove_absolute(temp)  # a stale conversion must not pass for a successful one
	var code := OS.execute("/usr/bin/sips", ["-s", "format", "jpeg", "-Z", "4096", path, "--out", temp], output)
	if code != 0 or not FileAccess.file_exists(temp):
		return null
	var image := Image.load_from_file(temp)
	if image == null or image.is_empty():
		return null
	_apply_orientation(image, _exif_orientation(temp))
	return image
