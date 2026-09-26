--!strict
--!native
--!optimize 2

const MAX_CODEPOINT: number = 0x10FFFF

const EscapeMap: { [string]: string } = {
	["&"] = "&amp;";
	["<"] = "&lt;";
	[">"] = "&gt;";
	["\""] = "&quot;";
	["'"] = "&apos;";
}

const UnescapeMap: { [string]: string } = {
	["amp"] = "&";
	["lt"] = "<";
	["gt"] = ">";
	["quot"] = "\"";
	["apos"] = "'";
	["nbsp"] = "\u{A0}";
}

const function Codepoint(Value: number?): string?
	if not Value or Value ~= Value or Value <= 0 or Value > MAX_CODEPOINT then return nil end
	if Value >= 0xD800 and Value <= 0xDFFF then return nil end

	return utf8.char(Value)
end

const function Decode(Entity: string): string?
	const Named: string? = UnescapeMap[Entity]; if Named then return Named end
	if string.byte(Entity) ~= 35 then return nil end

	const Marker: number? = string.byte(Entity, 2)

	if Marker == 120 or Marker == 88 then
		const Digits: string = string.sub(Entity, 3)
		if Digits == "" or #Digits > 8 or string.find(Digits, "%X") then return nil end

		return Codepoint(tonumber(Digits, 16))
	end

	const Digits: string = string.sub(Entity, 2)
	if Digits == "" or #Digits > 8 or string.find(Digits, "%D") then return nil end

	return Codepoint(tonumber(Digits))
end

const function Escape(String: string): string
	const Escaped: string = string.gsub(String, "[&<>\"']", EscapeMap)

	return Escaped
end

const function Unescape(String: string): string
	if not string.find(String, "&", 1, true) then return String end

	const Unescaped: string = string.gsub(String, "&(#?%w+);", function(Entity: string): string
		return Decode(Entity) or `&{Entity};`
	end)

	return Unescaped
end

return {
	Escape = Escape;
	Unescape = Unescape;
	Decode = Decode;
}
