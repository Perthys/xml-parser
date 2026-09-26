--!strict
--!native
--!optimize 2

const Node = require("./Node")
const Entities = require("./Entities")

type Node = Node.Node
type Attribute = Node.Attribute

const LESS: number = string.byte("<")
const GREATER: number = string.byte(">")
const SLASH: number = string.byte("/")
const EQUALS: number = string.byte("=")
const DOUBLE_QUOTE: number = string.byte("\"")
const SINGLE_QUOTE: number = string.byte("'")
const EXCLAMATION: number = string.byte("!")
const QUESTION: number = string.byte("?")
const UNDERSCORE: number = string.byte("_")
const COLON: number = string.byte(":")

const function IsSpace(Byte: number?): boolean
	return Byte == 32 or Byte == 9 or Byte == 10 or Byte == 13 or Byte == 12
end

const function IsNameStart(Byte: number?): boolean
	if not Byte then return false end

	return (Byte >= 97 and Byte <= 122) or (Byte >= 65 and Byte <= 90) or Byte == UNDERSCORE or Byte == COLON or Byte >= 128
end

const function IsNameEnd(Byte: number?): boolean
	return Byte == nil or IsSpace(Byte) or Byte == SLASH or Byte == GREATER or Byte == EQUALS or Byte == LESS or Byte == QUESTION
end

const function SkipSpace(String: string, Position: number, Limit: number): number
	local Index: number = Position

	while Index <= Limit and IsSpace(string.byte(String, Index)) do Index += 1 end

	return Index
end

const function FindTagEnd(String: string, Position: number, Size: number): number?
	local Index: number = Position
	local AfterEquals: boolean = false

	while Index <= Size do
		const Byte: number = string.byte(String, Index)

		if Byte == GREATER then return Index end
		if Byte == LESS then return nil end

		if AfterEquals and (Byte == DOUBLE_QUOTE or Byte == SINGLE_QUOTE) then
			const Closing: number? = string.find(String, if Byte == DOUBLE_QUOTE then "\"" else "'", Index + 1, true)
			if not Closing then return nil end

			Index = Closing + 1
			AfterEquals = false

			continue
		end

		if Byte == EQUALS then
			AfterEquals = true
		elseif not IsSpace(Byte) then
			AfterEquals = false
		end

		Index += 1
	end

	return nil
end

const function ReadName(String: string, Position: number, Limit: number): (string, number)
	local Index: number = Position

	while Index <= Limit and not IsNameEnd(string.byte(String, Index)) do Index += 1 end

	return string.sub(String, Position, Index - 1), Index
end

const function ReadAttributes(String: string, Position: number, Limit: number): { Attribute }?
	local Attributes: { Attribute }? = nil
	local Index: number = SkipSpace(String, Position, Limit)

	while Index <= Limit do
		const Byte: number = string.byte(String, Index)

		if Byte == SLASH or IsSpace(Byte) then Index += 1; continue end

		local NameEnd: number = Index

		while NameEnd <= Limit do
			const Current: number = string.byte(String, NameEnd)
			if IsSpace(Current) or Current == EQUALS or Current == SLASH then break end

			NameEnd += 1
		end

		if NameEnd == Index then Index += 1; continue end

		const Name: string = string.sub(String, Index, NameEnd - 1)
		local Value: string = ""
		local Next: number = SkipSpace(String, NameEnd, Limit)

		if string.byte(String, Next) == EQUALS then
			Next = SkipSpace(String, Next + 1, Limit)

			const Quote: number? = string.byte(String, Next)

			if Quote == DOUBLE_QUOTE or Quote == SINGLE_QUOTE then
				const Closing: number = string.find(String, if Quote == DOUBLE_QUOTE then "\"" else "'", Next + 1, true) or Limit + 1

				Value = string.sub(String, Next + 1, math.min(Closing, Limit + 1) - 1)
				Next = Closing + 1
			else
				local ValueEnd: number = Next

				while ValueEnd <= Limit and not IsSpace(string.byte(String, ValueEnd)) do ValueEnd += 1 end

				Value = string.sub(String, Next, ValueEnd - 1)
				Next = ValueEnd
			end
		end

		if not Attributes then Attributes = {} end
		table.insert(Attributes :: { Attribute }, {Name = Name; Value = Value})

		Index = Next
	end

	return Attributes
end

const function MatchClose(Stack: { Node }, Depth: number, Tag: string): number?
	for Index = Depth, 2, -1 do
		if Stack[Index].TagType == Tag then return Index end
	end

	const Lowered: string = string.lower(Tag)

	for Index = Depth, 2, -1 do
		const Open: string? = Stack[Index].TagType
		if Open and string.lower(Open) == Lowered then return Index end
	end

	return nil
end

const function GenerateTreeFromXML(self: unknown, Source: string?): Node
	const String: unknown = if Source == nil then self else Source

	if typeof(String) ~= "string" then error("GenerateTreeFromXML expects a string") end

	const Text: string = String :: string
	const Size: number = #Text

	const Root: Node = Node.new("ROOT")
	const Stack: { Node } = {Root}

	local Current: Node = Root
	local Depth: number = 1
	local TextStart: number = 1
	local Search: number = 1

	const function Flush(Stop: number): ()
		if Stop >= TextStart then table.insert(Current.Children, Node.new("STRING", {Text = string.sub(Text, TextStart, Stop)})) end
	end

	while Search <= Size do
		const Start: number? = string.find(Text, "<", Search, true)
		if not Start then break end

		const Position: number = Start :: number
		const Next: number? = string.byte(Text, Position + 1)

		local Resume: number? = nil

		if Next == EXCLAMATION then
			if string.sub(Text, Position + 2, Position + 3) == "--" then
				const Finish: number? = string.find(Text, "-->", Position + 4, true)

				if Finish then
					Flush(Position - 1)
					table.insert(Current.Children, Node.new("COMMENT", {Text = string.sub(Text, Position + 4, Finish - 1)}))
					Resume = Finish + 3
				end
			elseif string.sub(Text, Position + 2, Position + 8) == "[CDATA[" then
				const Finish: number? = string.find(Text, "]]>", Position + 9, true)

				if Finish then
					Flush(Position - 1)
					table.insert(Current.Children, Node.new("STRING", {Text = Entities.Escape(string.sub(Text, Position + 9, Finish - 1))}))
					Resume = Finish + 3
				end
			end
		elseif Next == QUESTION then
			if IsNameStart(string.byte(Text, Position + 2)) then
				const Finish: number? = string.find(Text, "?>", Position + 2, true)

				if Finish then
					const Tag: string, After: number = ReadName(Text, Position + 2, Finish - 1)

					Flush(Position - 1)
					table.insert(Current.Children, Node.new("PROLOG", {TagType = Tag; Attributes = ReadAttributes(Text, After, Finish - 1)}))
					Resume = Finish + 2
				end
			end
		elseif Next == SLASH then
			if IsNameStart(string.byte(Text, Position + 2)) then
				const Finish: number? = FindTagEnd(Text, Position + 2, Size)

				if Finish then
					const Tag: string = ReadName(Text, Position + 2, Finish - 1)
					const Matched: number? = MatchClose(Stack, Depth, Tag)

					Flush(Position - 1)

					if Matched then
						for Index = Depth, Matched, -1 do Stack[Index] = nil end

						Depth = Matched - 1
						Current = Stack[Depth]
					end

					Resume = Finish + 1
				end
			end
		elseif IsNameStart(Next) then
			const Finish: number? = FindTagEnd(Text, Position + 1, Size)

			if Finish then
				const Single: boolean = string.byte(Text, Finish - 1) == SLASH
				const Tag: string, After: number = ReadName(Text, Position + 1, Finish - 1)
				const Created: Node = Node.new(if Single then "SINGLE" else "TAG", {
					TagType = Tag;
					Attributes = ReadAttributes(Text, After, if Single then Finish - 2 else Finish - 1);
				})

				Flush(Position - 1)
				table.insert(Current.Children, Created)

				if not Single then
					Depth += 1
					Stack[Depth] = Created
					Current = Created
				end

				Resume = Finish + 1
			end
		end

		if Resume then
			TextStart = Resume :: number
			Search = Resume :: number
		else
			Search = Position + 1
		end
	end

	Flush(Size)

	return Root
end

return {
	GenerateTreeFromXML = GenerateTreeFromXML;
}
