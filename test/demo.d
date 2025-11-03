/+ dub.json:
    {
	"authors": [
		"Dmitry Olshansky"
	],
	"copyright": "Copyright © 2025, Dmitry Olshansky",
	"dependencies": {
		"photon-mustache": { "path": ".." }
	},
    "dflags" : ["-J."],
	"description": "A test for mustache API",
	"license": "BOOST",
	"name": "demo"
}
+/
module test.demo;

import std.stdio;
import photon.mustache;

struct Context {
  string name;
  double value;
  double taxed_value;
  bool in_ca;
}

alias templ = mustache!(import("template.mustache"));

void main()
{
  auto ctx = Context("Chris", 1000, 1000 - 0.4 * 1000, true);
  auto writer = stdout.lockingTextWriter();
  templ(ctx, writer);
}
