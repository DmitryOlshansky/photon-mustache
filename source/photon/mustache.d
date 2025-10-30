module photon.mustache;

import std.array;
import std.range.primitives;

template mustache(alias templ, C) {
    mixin(parseAndEmit!C(templ));
}

void htmlEscape(T, Output)(T value, ref Output output)
if (isOutputRange!(Output, char)) {
    static if (is(T : long)) {
        toStr(value, output);
    } else if (is(T : const(char)[])) {
        foreach (char c; value) {
            if (c == '&') {
                output.put("&amp;");
            } else if (c == '<') {
                output.put("&lt;");
            } else if (c == '>') {
                output.put("&gt;");
            } else if (c == '"') {
                output.put("&quot;");
            } else if (c == '\'') {
                output.put("&#39;");
            } else {
                output.put(c);
            }
        }
    }
    else {
        import std.conv;
        htmlEscape(value.to!string, output);
    }
}

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

interface Node {
    void compile(ref CodeGen gen);
}

class Text : Node {
    string text;
    
    this(string text) {
        this.text = text;
    }

    override void compile(ref CodeGen gen) {
        gen.emitText(text);
    }
}

class Variable : Node {
    string context;
    string varPath;

    this(string context, string varPath) {
        this.context = context;
        this.varPath = varPath;
    }

    override void compile(ref CodeGen gen) {
        if (varPath == ".") {

        }
    }
}

class Section : Node {
    string context;
    string section;
    bool inverted;
    Node[] nodes;

    override void compile(ref CodeGen gen) {

    }
}

struct Parser {
    import std.algorithm, std.range, std.conv, std.uni;
    string templ;
    string open = "{{", close = "}}";
    string[] stack;
    Node[] nodes;
    size_t cur = 0;

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
        cur += close.length;
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

    Node parse() {
        size_t last = cur;
        while (cur < templ.length) {
            if (templ[cur..$].startsWith(open)) {
                if (last != cur) nodes ~= new Text(templ[last..cur]);
                Tag tag = parseTag();
                last = cur;
            }
            else {
                cur++;
            }
        }
        return new Text(templ);
    }
}

struct CodeGen {
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


    void emitText(string text) {
        putLine("sink.put(\""~escaped(text)~"\");");
    }

}

string parseAndEmit(C)(string templ) {
    auto gen = CodeGen();
    gen.putLine("void mustache(C, Output)(C context, ref Output sink) {");
    gen.incIndent();
    auto parser = Parser(templ);
    auto tree = parser.parse();
    tree.compile(gen);
    gen.decIndent();
    gen.putLine("}");
    return gen.code.data;
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
