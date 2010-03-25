module ast.namespace;

import ast.types, ast.fun, ast.variable;

import tools.ctfe, tools.base: stuple;
class Namespace {
  Namespace sup;
  template Kind(T, string Name) {
    mixin(`
      Stuple!(string, T)[] $NAMEfield;
      void add$NAME(T t) {
        static if (is(typeof(t.sup)))
          t.sup = this;
        $NAMEfield ~= stuple(t.name, t);
      }
      T lookup$NAME(string name) {
        // logln("Lookup ", name, " as $NAME in ", $NAMEfield);
        foreach (entry; $NAMEfield)
          if (entry._0 == name) return entry._1;
        if (sup) return sup.lookup$NAME(name);
        return null;
      }
    `.ctReplace("$NAME", Name));
  }
  mixin Kind!(Class, "Class");
  mixin Kind!(Function, "Fun");
  mixin Kind!(Variable, "Var");
  abstract string mangle(string name, Type type);
}

Function lookupFun(Namespace ns, string name) {
  if (auto res = ns.lookupFun(name)) return res;
  assert(false, "No such identifier: "~name);
}

Class lookupClass(Namespace ns, string name) {
  if (auto res = ns.lookupClass(name)) return res;
  assert(false, "No such identifier: "~name);
}

Variable lookupVar(Namespace ns, string name) {
  if (auto res = ns.lookupVar(name)) return res;
  assert(false, "No such identifier: "~name);
}