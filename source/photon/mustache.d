module photon.mustache;

import std.array;
import std.range.primitives;

template mustache(alias templ) {
    bool hasValue(T)(T value) {
        static if(is(T : bool)) {
            return value;
        } else {
            return !value.empty;
        }
    }
    enum code = parseAndEmit(templ);
    //pragma(msg, code);
    mixin(code);
}

void htmlEscape(T, Output)(T value, ref Output output)
if (isOutputRange!(Output, char)) {
    static if (is(T : long)) {
        toStr(value, output);
    } else static if (is(T : const(char)[])) {
        size_t last = 0;
        foreach (i, char c; value) {
            if (c == '&') {
                output.put(value[last..i]);
                last = i + 1;
                output.put("&amp;");
            } else if (c == '<') {
                output.put(value[last..i]);
                last = i + 1;
                output.put("&lt;");
            } else if (c == '>') {
                output.put(value[last..i]);
                last = i + 1;
                output.put("&gt;");
            } else if (c == '"') {
                output.put(value[last..i]);
                last = i + 1;
                output.put("&quot;");
            } else if (c == '\'') {
                output.put(value[last..i]);
                last = i + 1;
                output.put("&#39;");
            }
        }
        output.put(value[last..$]);
    }
    else {
        import std.conv;
        htmlEscape(value.to!string, output);
    }
}
pure @safe:

private:

version(unittest) string htmlEscaped(T)(T value) pure {
    Appender!(char[]) app;
    htmlEscape(value, app);
    return app.data;
}

unittest {
    assert("<html>".htmlEscaped == "&lt;html&gt;");
    assert("\"class\"".htmlEscaped == "&quot;class&quot;");
    assert("a&'b".htmlEscaped == "a&amp;&#39;b");
    assert("a&b&c".htmlEscaped == "a&amp;b&amp;c");
}

void toStr(Output)(long value, ref Output output) {
    static immutable table = "0123456789";
    static immutable min = "-9223372036854775808";
    char[16] chars=void;
    size_t i = 15;
    if (value == long.min) {
        output.put(min);
        return;
    }
    bool minus = false;
    if (value < 0) {
        minus = true;
        value = -value;
    }
    do {
        chars[i--] = table[value % 10];
        value /= 10;
    } while (value != 0);
    if (minus) {
        chars[i--] = '-';
    }
    output.put(chars[i+1..$]);
}

version(unittest) string str(long v) pure {
    Appender!(char[]) app;
    v.toStr(app);
    return app.data;
}

unittest {
    assert(7.str == "7");
    assert(10.str == "10");
    assert(123.str == "123");
    assert((-1L).str == "-1");
    assert((-321L).str == "-321");
    assert(long.min.str == "-9223372036854775808");
    //assert(long.min.str == "")
}

alias CodeSink = Appender!(char[]);

enum TagType {
    VAR,
    SECTION_OPEN,
    INVERTED_SECTION_OPEN,
    SECTION_CLOSE
};

struct Tag {
    TagType type;
    string value;
}

struct ContextState {
pure @safe:
    import std.conv;
    int depth;

    string context() => depth == 0 ? "context" : "__c"~to!string(depth);
}

interface Node {
pure @safe:
    void prettyPrint(ref Appender!(char[]) output, int indent = 0);
    void propagateContext(ref ContextState cs);
    void compile(ref CodeGen gen);
}

string variableRef(string context, string path) {
    if (path == ".") return context;
    else {
        return context ~ "." ~ path;
    }
}

class Text : Node {
pure @safe:
    import std.string;
    string text;
    
    this(string text) {
        this.text = text;
    }

    override void propagateContext(ref ContextState cs){}

    override void compile(ref CodeGen gen) {
        gen.putLine("sink.put(\""~escaped(text)~"\");");
    }

    void prettyPrint(ref Appender!(char[]) output, int indent) {
        foreach (_; 0..indent) output.put(' ');
        output.put("Text(\"");
        output.put(text.replace("\"", "\\\"").replace("\r", "\\r").replace("\n", "\\n"));
        output.put("\")\n");
    }
}

class Variable : Node {
pure @safe:
    string context;
    string varPath;

    this(string varPath) {
        this.varPath = varPath;
    }

    override void propagateContext(ref ContextState cs) {
        context = cs.context;
    }

    override void compile(ref CodeGen gen) {
        gen.putLine("htmlEscape("~variableRef(context, varPath)~", sink);");
    }

    void prettyPrint(ref Appender!(char[]) output, int indent) {
        foreach (_; 0..indent) output.put(' ');
        output.put("Variable(");
        output.put(varPath);
        output.put(")\n");
    }
}

class Section : Node {
pure @safe:
    string context;
    string nextContext;
    string section;
    bool inverted, root;
    Node[] nodes;

    this(string section, bool inverted, bool root=false) {
        this.section = section;
        this.inverted = inverted;
        this.root = root;
    }

    void addNode(Node node) {
        nodes ~= node;
    }

    override void compile(ref CodeGen gen) {
        if (root) {
            foreach (node; nodes) {
                node.compile(gen);
            }
        } else {
            if (inverted) {
                gen.putLine("if (!hasValue("~variableRef(context, section)~")) {");
                gen.incIndent();
                gen.putLine("auto "~nextContext~" = "~context~";");
                foreach (node; nodes) {
                    node.compile(gen);
                }
                gen.decIndent();
                gen.putLine("}");
            } else {
                gen.putLine("static if(__traits(compiles, (){typeof("~variableRef(context, section)~") v; foreach(_; v){}})) {");
                gen.incIndent();
                gen.putLine("foreach("~nextContext~"; "~variableRef(context, section)~"){");
                gen.incIndent();
                foreach (node; nodes) {
                    node.compile(gen);
                }
                gen.decIndent();
                gen.putLine("}");
                gen.decIndent();
                gen.putLine("} else {");
                gen.incIndent();
                gen.putLine("auto "~nextContext~" = "~variableRef(context, section)~";");
                gen.putLine("if (hasValue("~nextContext~")) {");
                gen.incIndent();
                foreach (node; nodes) {
                    node.compile(gen);
                }
                gen.decIndent();
                gen.putLine("}");
                gen.decIndent();
                gen.putLine("}");
            }
        }
    }

    void propagateContext(ref ContextState cs) {
        if (root) {
            nextContext = context;
            foreach (node; nodes) {
                node.propagateContext(cs);
            }
        }
        else {
            context = cs.context;
            cs.depth++;
            nextContext = cs.context;
            foreach (node; nodes) {
                node.propagateContext(cs);
            }
            cs.depth--;
        }
    }

    void prettyPrint(ref Appender!(char[]) output, int indent) {
        foreach (_; 0..indent) output.put(' ');
        if (inverted) output.put("InvSection(");
        else output.put("Section(");
        output.put(section);
        output.put(")\n");
        foreach (node; nodes) {
            node.prettyPrint(output, indent + 4);
        }
        foreach (_; 0..indent) output.put(' ');
        output.put("SectionEnd(");
        output.put(section);
        output.put(")\n");
    }
}

struct Parser {
    import std.algorithm, std.range, std.conv, std.uni;
    string templ;
    string open = "{{", close = "}}";
    string[] stack;
    Section[] sections;
    size_t cur = 0;
pure @safe:
    this(string input) {
        templ = input;
        sections ~= new Section("context", false, true);
    }

    Section top() {
        return sections[$-1];
    }

    void push(string section, bool inverted) {
        Section sec = new Section(section, inverted);
        top.addNode(sec);
        sections ~= sec;
    }

    void pop() {
        sections = sections[0..$-1];
    }

    void enforce(bool cond, string error) {
        if (!cond) {
            size_t line = templ[0..cur].count("\n") + 1;
            size_t col = templ[0..cur].retro().countUntil('\n');
            throw new Exception("Mustache template at " ~ to!string(line) ~ ":" ~ to!string(col) ~ ": " ~ error);
        }
    }

    Tag parseTag() {
        cur += open.length;
        enforce (cur < templ.length, "unexpected eof while looking for closing delimeter");
        auto rest = templ[cur..$].find(close);
        enforce(!rest.empty, "unexpected eof while looking for closing delimeter");
        auto slice = templ[cur..$-rest.length];
        cur += slice.length + close.length;
        TagType type;
        if (slice.startsWith("#")) {
            slice = slice[1..$];
            type = TagType.SECTION_OPEN;
        } else if (slice.startsWith("^")) {
            slice = slice[1..$];
            type = TagType.INVERTED_SECTION_OPEN;
        } else if (slice.startsWith("/")) {
            slice = slice[1..$];
            type = TagType.SECTION_CLOSE;
        } else if (slice.startsWith("=") && slice.endsWith("=") && slice.length > 1) {
            slice = slice[1..$-1];
        } else if (slice == "." || (slice[0].isAlpha() && slice.all!(c => c.isAlpha || c.isNumber))) {
            type = TagType.VAR;
        } else {
            enforce(false, "unknown tag type `"~slice~"`");
        }
        return Tag(type, slice);
    }

    Section parse() {
        size_t last = cur;
        while (cur < templ.length) {
            if (templ[cur..$].startsWith(open)) {
                if (last != cur) top.addNode(new Text(templ[last..cur]));
                Tag tag = parseTag();
                last = cur;
                if (tag.type == TagType.VAR) {
                    top.addNode(new Variable(tag.value));
                } else if(tag.type == TagType.SECTION_OPEN) {
                    push(tag.value, false);
                } else if(tag.type == TagType.INVERTED_SECTION_OPEN) {
                    push(tag.value, true);
                } else if (tag.type == TagType.SECTION_CLOSE) {
                    enforce(tag.value == top.section, "name mismatch in closing tag, expected `"~top.section~"` found `"~tag.value~"`");
                    pop();
                }
            }
            else {
                cur++;
            }
        }
        if (last != cur) top.addNode(new Text(templ[last..$]));
        enforce(sections.length == 1, "unclosed section `"~top.section~"`");
        return top;
    }
}

unittest {
    static string repr(string templ) pure {
        auto app = appender!(char[]);
        auto p = Parser(templ);
        p.parse().prettyPrint(app, 0);
        return app.data;
    }
    assert(repr("Hello, world!") == 
`Section(context)
    Text("Hello, world!")
SectionEnd(context)
`);
    assert(repr("Hi, {{name}}!") == 
`Section(context)
    Text("Hi, ")
    Variable(name)
    Text("!")
SectionEnd(context)
`);
    assert(repr("{{#action}} {{var}} {{/action}}\nTEXT") == 
`Section(context)
    Section(action)
        Text(" ")
        Variable(var)
        Text(" ")
    SectionEnd(action)
    Text("\nTEXT")
SectionEnd(context)
`);
    assert(repr("{{^sect}}{{#sect2}}{{/sect2}}{{/sect}}") == 
 `Section(context)
    InvSection(sect)
        Section(sect2)
        SectionEnd(sect2)
    SectionEnd(sect)
SectionEnd(context)
`);

}

struct CodeGen {
pure @safe:
    CodeSink code;
    int indent;

    enum INDENT = 4;

    void putLine(string line) {
        foreach (_; 0..indent)
            code.put(' ');
        code.put(line);
        code.put('\n');
    }

    void incIndent() {
        indent += INDENT;
    }

    void decIndent() {
        assert(indent >= INDENT);
        indent -= INDENT;
    }
}

string parseAndEmit(string templ) {
    auto gen = CodeGen();
    gen.putLine("void mustache(C, Output)(C context, ref Output sink) {");
    gen.incIndent();
    auto parser = Parser(templ);
    auto tree = parser.parse();
    ContextState cs;
    tree.context = "context";
    tree.propagateContext(cs);
    tree.compile(gen);
    gen.decIndent();
    gen.putLine("}");
    return gen.code.data;
}

unittest {
    import std.stdio;
    string render(alias templ, C)(C value) pure {
        Appender!(string) app;
        mustache!templ(value, app);
        return app.data;
    }
    struct C {
        string value;
    }
    struct C2 {
        C c;
        int value;
        double d;
    }
    C2 ctx = C2(C(""), 42, 1.5);
    struct C3 {
        string val;
        C[] values;
    }
    struct C4 {
        C3[] cs;
    }
    auto c4 = C4([C3("<", [C("A"), C("B")]), C3(">", [C("C"), C("D")])]);
    assert(render!"{{value}}"(C("OK")) == "OK");
    assert(render!"{{#.}}{{value}}{{/.}}"([C("1"), C("2")]) == "12");
    assert(render!"{{^c.value}}{{value}} is the answer. D={{d}}{{/c.value}}"(ctx) == "42 is the answer. D=1.5");
    assert(render!"{{#cs}}{{val}}:{{#values}}{{value}}.{{/values}}{{/cs}}"(c4) == "&lt;:A.B.&gt;:C.D.");
}

string escaped(string str) {
    Appender!string result;
    size_t last = 0, cur = 0;
    while (cur < str.length) {
        if (str[cur] == '"') {
            result ~= str[last..cur];
            result ~= "\\\"";
            last = cur + 1;
        }
        cur++;
    }
    if (last == 0) return str;
    result ~= str[last..cur];
    return result.data;
}

unittest {
    assert("".escaped is "");
    assert("123".escaped is "123");
    assert("\"".escaped == "\\\"");
    assert("a\"".escaped == "a\\\"");
    assert("\"b".escaped == "\\\"b");
    assert("a\"b".escaped == "a\\\"b");
    assert("a\"b\"".escaped == "a\\\"b\\\"");
    assert("a\"b\"c".escaped == "a\\\"b\\\"c");
}
