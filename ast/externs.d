module ast.externs;

import ast.base, ast.fun, ast.namespace, ast.pointer;

class ExternCGlobVar : CValue, Named {
  IType type;
  string name;
  mixin defaultIterate!();
  ExternCGlobVar dup() { return this; /* invariant */ }
  this(IType t, string n) {
    this.type = t;
    this.name = n;
  }
  override {
    IType valueType() { return type; }
    string getIdentifier() { return name; }
    void emitAsm(AsmFile af) { af.pushStack(name, type); }
    void emitLocation(AsmFile af) { af.pushStack(qformat("$", name), voidp); }
    string toString() { return Format("extern(C) global ", name, " of ", type); }
  }
}

Object gotMarkStdCall(ref string text, ParseCb cont, ParseCb rest) {
  IType ty;
  if (!rest(text, "type", &ty))
    text.failparse("Expected type to mark as std-call. ");
  auto fp = fastcast!(FunctionPointer) (resolveType(ty));
  if (!fp)
    text.failparse(ty, " is not a function pointer! ");
  auto fp2 = new FunctionPointer;
  fp2.ret = fp.ret;
  fp2.args = fp.args;
  fp2.stdcall = true;
  return fp2;
}
mixin DefaultParser!(gotMarkStdCall, "type.mark_stdcall", "911", "_markStdCall");

import ast.modules;
Object gotExtern(ref string text, ParseCb cont, ParseCb rest) {
  auto t2 = text;
  bool isStdcall;
  if (!t2.accept("extern(")) return null;
  if (!t2.accept("C")) {
    if (!t2.accept("Windows")) return null;
    isStdcall = true;
  }
  if (!t2.accept(")")) return null;
  string tx;
  bool grabFun() {
    auto fun = new Function;
    fun.extern_c = true;
    New(fun.type);
    fun.type.stdcall = isStdcall;
    auto t3 = t2;
    if (test(fun.type.ret = fastcast!(IType)~ rest(t3, "type")) &&
        t3.gotIdentifier(fun.name) &&
        t3.gotParlist(fun.type.params, rest) &&
        t3.accept(";")
      )
    {
      t2 = t3;
      namespace().add(fun);
      return true;
    } else {
      tx = t3;
      return false;
    }
  }
  bool grabVar() {
    auto t3 = t2;
    IType type; string name;
    if (rest(t3, "type", &type) && t3.gotIdentifier(name) && t3.accept(";")) {
      t2 = t3;
      auto gv = new ExternCGlobVar(type, name);
      namespace().add(gv);
      return true;
    } else {
      tx = t3;
      return false;
    }
  }
  bool grabFunDef() {
    auto t3 = t2;
    Function fun;
    if (!rest(t3, "tree.fundef", &fun)) return false;
    fun.extern_c = true;
    logln("got fundef ", fun.name);
    current_module().entries ~= fun;
    t2 = t3;
    return true;
  }
  void fail() {
    tx.failparse("extern parsing failed");
  }
  if (t2.accept("{")) {
    do {
      if (t2.accept("}")) goto success;
    } while (grabFun() || grabVar() || grabFunDef());
    t2.failparse("Expected closing '}' for extern(C)!");
    success:;
  } else if (!grabFun() && !grabVar() && !grabFunDef()) fail;
  text = t2;
  return Single!(NoOp);
}
mixin DefaultParser!(gotExtern, "tree.toplevel.extern_c");
