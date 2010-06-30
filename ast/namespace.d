module ast.namespace;

import ast.base;

import tools.ctfe, tools.base: stuple, Format, Repeat;
class Namespace {
  Namespace sup;
  T get(T)() {
    auto cur = this;
    do {
      if (auto res = cast(T) cur) return res;
    } while (null !is (cur = cur.sup));
    throw new Exception(Format("No ", T.stringof, " above ", this, "!"));
  }
  Stuple!(string, Object)[] field;
  void select(T)(void delegate(string, T) dg) {
    foreach (entry; field)
      if (auto t = cast(T) entry._1)
        dg(entry._0, t);
  }
  void add(Named n) {
    auto name = n.getIdentifier();
    if (lookup(name))
      throw new Exception(Format(name, " already defined in ", this, ": ", lookup(name)));
    if (auto ns = cast(Namespace) n)
      ns.sup = this;
    field ~= stuple(name, cast(Object) n);
  }
  typeof(field) getCheckpt() { return field; }
  void setCheckpt(typeof(field) field) { this.field = field.dup; /* prevent clobbering */ }
  Object lookup(string name, bool local = false) {
    foreach (entry; field)
      if (entry._0 == name) return entry._1;
    if (sup) return sup.lookup(name, local);
    return null;
  }
  abstract string mangle(string name, IType type);
  abstract Stuple!(IType, string, int)[] stackframe();
}

T lookup(T)(Namespace ns, string name) {
  if (auto res = cast(T) ns.lookup(name)) return res;
  assert(false, "No such "~T.stringof~": "~name);
}

import tools.threads;
TLS!(Namespace) namespace;

import parseBase, tools.log;
Object gotNamed(ref string text, ParseCb cont, ParseCb rest) {
  string name, t2 = text;
  if (t2.gotIdentifier(name, true)) {
    retry:
    if (auto res = namespace().lookup(name)) {
      if (!text.accept(name)) throw new Exception("WTF! "~name~" at "~text.next_text());
      return res;
    }
    if (name.rfind(".") != -1) {
      name = name[0 .. name.rfind(".")]; // chop up what _may_ be members!
      goto retry;
    }
    error = "unknown identifier "~name;
  }
  return null;
}
