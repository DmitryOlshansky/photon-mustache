# photon-mustache

Compile-time [mustache](https://mustache.github.io/mustache.5.html) templating for photon-http and standalone.

## Example

Given template.mustache:
```mustache
Hello {{name}}
You have just won {{value}} dollars!
{{#in_ca}}
Well, {{taxed_value}} dollars, after taxes.
{{/in_ca}}
```

The following should render the template to the stdout:

```d
import std.stdio;
import photon.mustache;

struct Context {
  string name;
  double value;
  double taxed_value;
  bool in_ca;
}

static templ = mustache!(import("template.mustache"), Context);

void writeTemplate()
{
  auto ctx = Context("Chris", 1000, 1000 - 0.4 * 1000, true);
  templ(ctx, lockingTextWriter(stdout));
}
```

## API

photon-mustache is aimed for fastest rendering of compile-time known nested data structures, anything that is sliceable is considered a list and 
anything that supports opIndex with strings is considered a dynamic context and can subsequently be nested.

Internally mustache!(...) template generates a callable template that accepts value and an output range of char.

