local reader = {}
reader.__index = reader

export type Reader = {
	stream: buffer,
	offset: number,

	byte: (Reader) -> (number),
	string: (Reader) -> (string),
	number: (Reader) -> (number),
}

function reader.new(stream: string | buffer)
	stream = (type(stream) == "string" and buffer.fromstring(stream)) or stream

	local self = setmetatable({
		stream = stream,
		offset = 0
	}, reader)
	return self
end

function reader:byte(): number
	assert(self.offset + 1 <= buffer.len(self.stream), "out of range")
	local result = buffer.readu8(self.stream, self.offset)
	self.offset += 1
	return result
end

function reader:sbyte(): number
	assert(self.offset + 1 <= buffer.len(self.stream), "out of range")
	local result = buffer.readi8(self.stream, self.offset)
	self.offset += 1
	return result
end

function reader:string(): string
	local size = self:number()
	assert(self.offset + size <= buffer.len(self.stream), "out of range")

	if size == 0 then
		return ""
	else
		local str = buffer.readstring(self.stream, self.offset, size)
		self.offset += size

		return str
	end
end

function reader:number(): number
	local result = 0

	for i = 0, 4 do
		local value = self:byte()
		result = bit32.bor(result, bit32.lshift(bit32.band(value, 0x7F), i * 7))
		if not bit32.btest(value, 0x80) then
			break
		end
	end

	return result
end

function reader:bytes(size: number): { number }
	assert(self.offset + size <= buffer.len(self.stream), "out of range")
	local result = {}
	for i = 1, size do
		table.insert(result, self:byte())
	end
	return result
end

function reader:word()
	assert(self.offset + 4 <= buffer.len(self.stream), "out of range")
	local result = buffer.readu32(self.stream, self.offset)
	self.offset += 4
	return result
end

function reader:sword()
	assert(self.offset + 4 <= buffer.len(self.stream), "out of range")
	local result = buffer.readi32(self.stream, self.offset)
	self.offset += 4
	return result
end

function reader:float()
	assert(self.offset + 4 <= buffer.len(self.stream), "out of range")
	local result = buffer.readf32(self.stream, self.offset)
	self.offset += 4
	return result
end

function reader:double()
	assert(self.offset + 8 <= buffer.len(self.stream), "out of range")
	local result = buffer.readf64(self.stream, self.offset)
	self.offset += 8
	return result
end

return reader
