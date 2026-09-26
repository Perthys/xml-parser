--!strict

type Result = { Passed: number, Failed: number, Failures: { string } }

return function(XML: any): Result
	const Result: Result = {Passed = 0, Failed = 0, Failures = {}}

	const function Expect(Name: string, Actual: any, Expected: any): ()
		if Actual == Expected then Result.Passed += 1; return end

		Result.Failed += 1
		table.insert(Result.Failures, `{Name}: expected {tostring(Expected)}, got {tostring(Actual)}`)
	end

	const function Shape(Tree: any): string
		const Parts: { string } = {}

		const function Walk(Node: any): ()
			for _, Child: any in Node.Children do
				if Child.Type == "STRING" then
					table.insert(Parts, `"{Child.Text}"`)
				elseif Child.Type == "TAG" then
					table.insert(Parts, `{Child.TagType}(`)
					Walk(Child)
					table.insert(Parts, ")")
				elseif Child.Type == "SINGLE" then
					table.insert(Parts, `{Child.TagType}/`)
				elseif Child.Type == "COMMENT" then
					table.insert(Parts, `#{Child.Text}#`)
				elseif Child.Type == "PROLOG" then
					table.insert(Parts, `?{Child.TagType}`)
				end
			end
		end

		Walk(Tree)

		return table.concat(Parts, " ")
	end

	const function Parse(Source: string): string
		return Shape(XML.GenerateTreeFromXML(Source))
	end

	Expect("basic", Parse("<b>hi</b>"), "b( \"hi\" )")
	Expect("method call", Shape(XML:GenerateTreeFromXML("<i>x</i>")), "i( \"x\" )")
	Expect("nested", Parse("<b>a<i>b</i>c</b>"), "b( \"a\" i( \"b\" ) \"c\" )")
	Expect("single", Parse("a<br/>b"), "\"a\" br/ \"b\"")
	Expect("single spaced", Parse("a<br />b"), "\"a\" br/ \"b\"")
	Expect("comment", Parse("a<!-- x -->b"), "\"a\" # x # \"b\"")
	Expect("prolog", Parse("<?xml version=\"1.0\"?><a/>"), "?xml a/")
	Expect("cdata", Parse("<![CDATA[a<b>&c]]>"), "\"a&lt;b&gt;&amp;c\"")

	Expect("less than in text", Parse("a < b > c"), "\"a < b > c\"")
	Expect("less than digit", Parse("1<2 and 3>2"), "\"1<2 and 3>2\"")
	Expect("less than then tag", Parse("x < <b>y</b>"), "\"x < \" b( \"y\" )")
	Expect("unterminated tag stays text", Parse("<b oops"), "\"<b oops\"")
	Expect("tag broken by less than", Parse("<b <i>x</i>"), "\"<b \" i( \"x\" )")
	Expect("stray quote in text", Parse("it's <b>fine</b> \"ok\""), "\"it's \" b( \"fine\" ) \" \"ok\"\"")
	Expect("stray quote in tag name area", Parse("<b x\">y</b>"), "b( \"y\" )")
	Expect("greater inside quoted value", Parse("<a href=\"x>y\">t</a>"), "a( \"t\" )")
	Expect("unclosed comment is text", Parse("a<!-- b"), "\"a<!-- b\"")

	Expect("case insensitive close", Parse("<B>x</b>y"), "B( \"x\" ) \"y\"")
	Expect("exact close preferred", Parse("<b><B>x</B></b>"), "b( B( \"x\" ) )")
	Expect("unmatched close ignored", Parse("a</i>b"), "\"a\" \"b\"")
	Expect("mismatched close pops to match", Parse("<b><i>x</b>y"), "b( i( \"x\" ) ) \"y\"")

	const Attributes: any = XML.GenerateTreeFromXML("<font color=\"#fff\" size=18 face='Arial' bold>t</font>").Children[1]
	Expect("attr quoted", Attributes:GetAttribute("color"), "#fff")
	Expect("attr unquoted", Attributes:GetAttribute("size"), "18")
	Expect("attr single quoted", Attributes:GetAttribute("face"), "Arial")
	Expect("attr boolean", Attributes:GetAttribute("bold"), "")
	Expect("attr count", #Attributes.Attributes, 4)

	const Spaced: any = XML.GenerateTreeFromXML("<a href = \"x\" />").Children[1]
	Expect("attr spaced equals", Spaced:GetAttribute("href"), "x")
	Expect("attr spaced single", Spaced.Type, "SINGLE")

	const Entity: any = XML.GenerateTreeFromXML("<a t=\"&lt;&amp;\">&#65;&#x42;&#X43;</a>").Children[1]
	Expect("attr entity", Entity:GetAttribute("t"), "<&")
	Expect("text numeric entities", Entity.Children[1]:GetText(), "ABC")

	Expect("huge decimal entity", XML.Unescape("&#99999999999999999999;"), "&#99999999999999999999;")
	Expect("above max codepoint", XML.Unescape("&#x110000;"), "&#x110000;")
	Expect("surrogate", XML.Unescape("&#xD800;"), "&#xD800;")
	Expect("zero", XML.Unescape("&#0;"), "&#0;")
	Expect("bad hex", XML.Unescape("&#xZZ;"), "&#xZZ;")
	Expect("unknown named", XML.Unescape("&bogus;"), "&bogus;")
	Expect("nbsp", XML.Unescape("a&nbsp;b"), "a\u{A0}b")
	Expect("no entities fast path", XML.Unescape("plain"), "plain")
	Expect("emoji entity", XML.Unescape("&#x1F600;"), "\u{1F600}")
	Expect("escape", XML.Escape("<a & \"b\" 'c'>"), "&lt;a &amp; &quot;b&quot; &apos;c&apos;&gt;")

	const RoundTrips: { string } = {
		"<b>hi</b>",
		"a<br/>b",
		"<font color=\"#fff\" size=\"18\">t</font>",
		"<!-- c --><?xml version=\"1.0\"?>",
		"<a t='say \"hi\"'>x</a>",
	}

	for _, Source: string in RoundTrips do
		Expect(`roundtrip {Source}`, XML.GenerateXMLFromTree(XML.GenerateTreeFromXML(Source)), Source)
	end

	const Mixed: any = XML.GenerateTreeFromXML("<a t=\"it's &quot;x&quot;\"/>")
	Expect("serialize both quotes", XML.GenerateXMLFromTree(XML.GenerateTreeFromXML(XML.GenerateXMLFromTree(Mixed))), XML.GenerateXMLFromTree(Mixed))

	const Deep: string = string.rep("<b>", 3000) .. "x" .. string.rep("</b>", 3000)
	const Started: number = os.clock()
	const DeepTree: any = XML.GenerateTreeFromXML(Deep)
	Expect("deep nesting parses", DeepTree.Children[1].TagType, "b")
	Expect("deep nesting fast", os.clock() - Started < 0.5, true)

	const Noise: string = string.rep("a < b < c <", 5000)
	const NoiseStarted: number = os.clock()
	Expect("many stray less than stay text", #XML.GenerateTreeFromXML(Noise).Children, 1)
	Expect("many stray less than fast", os.clock() - NoiseStarted < 0.5, true)

	const Quotes: string = "<b " .. string.rep("x=\"", 2000)
	const QuotesStarted: number = os.clock()
	XML.GenerateTreeFromXML(Quotes)
	Expect("unterminated quotes bounded", os.clock() - QuotesStarted < 1, true)

	return Result
end
