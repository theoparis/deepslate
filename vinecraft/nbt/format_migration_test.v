module nbt

fn test_format_bedrock_little_endian_compound_vector() ! {
	mut root := make_compound()
	root.set('v', make_int(0x01020304))
	mut writer := ByteWriter{}
	write_root(mut writer, '', root)!
	assert writer.buf == [u8(0x0a), 0, 0, 3, 1, 0, `v`, 4, 3, 2, 1, 0]
	mut reader := new_reader(writer.buf)
	decoded := read_root(mut reader)!
	assert decoded.name == ''
	assert decoded.tag.get_int('v', 0) == 0x01020304
	assert reader.eof()
}

fn test_format_utf8_nested_and_arrays_roundtrip() ! {
	mut root := make_compound()
	root.set('str', make_string('héllo'))
	mut nested := make_compound()
	nested.set('x', make_int(7))
	root.set('nested', nested)
	mut list := make_list(.int_tag)
	for i in 0 .. 4 { list.list << make_int(i * i) }
	root.set('list', list)
	root.set('ba', make_byte_array([u8(1), 2, 3, 250]))
	root.set('ia', make_int_array([-1, 0, 65536]))
	mut writer := ByteWriter{}
	write_root(mut writer, 'root', root)!
	mut reader := new_reader(writer.buf)
	decoded := read_root(mut reader)!
	assert decoded.name == 'root'
	assert decoded.tag.get_string('str', '') == 'héllo'
	assert (decoded.tag.find('nested') or { panic('missing nested') }).get_int('x', 0) == 7
	assert (decoded.tag.find('list') or { panic('missing list') }).list_num(3, 0) == 9
	assert (decoded.tag.find('ba') or { panic('missing byte array') }).bytes == [
		u8(1),
		2,
		3,
		250,
	]
	assert (decoded.tag.find('ia') or { panic('missing int array') }).ints == [-1, 0, 65536]
	assert reader.eof()
}
