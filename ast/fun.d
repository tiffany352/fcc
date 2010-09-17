module ast.fun;

import ast.namespace, ast.base, ast.variable, asmfile, ast.types,
  ast.constant, ast.pointer;

import tools.functional;

class FunSymbol : Symbol {
  Function fun;
  this(Function fun) {
    this.fun = fun;
    super(fun.mangleSelf());
  }
  private this() { }
  mixin DefaultDup!();
  string toString() { return Format("symbol<", name, ">"); }
  override IType valueType() {
    auto res = new FunctionPointer;
    res.ret = fun.type.ret;
    res.args = fun.type.params /map/ ex!("a, b -> a");
    res.args ~= Single!(SysInt);
    return res;
  }
}

extern(C) Object nf_fixup__(Object obj, Expr mybase);

class Function : Namespace, Tree, Named, SelfAdding {
  string name;
  Expr getPointer() {
    return new FunSymbol(this);
  }
  FunctionType type;
  Tree tree;
  bool extern_c = false;
  mixin defaultIterate!(tree);
  string toString() { return Format("fun ", name, " ", type, " <- ", sup); }
  // add parameters to namespace
  int _framestart;
  Function alloc() { return new Function; }
  Function dup() {
    auto res = alloc();
    res.name = name;
    res.type = type;
    res.extern_c = extern_c;
    res.tree = tree.dup;
    res._framestart = _framestart;
    res.sup = sup;
    res.field = field;
    res.rebuildCache;
    return res;
  }
  FunCall mkCall() {
    auto res = new FunCall;
    res.fun = this;
    return res;
  }
  int fixup() {
    // cdecl: 0 old ebp, 4 return address, 8 parameters .. I think.
    add(new Variable(Single!(SizeT), "__old_ebp", 0));
    add(new Variable(Single!(SizeT), "__fun_ret", 4));
    int cur = _framestart = 8;
    // TODO: alignment
    foreach (param; type.params) {
      if (param._1) {
        _framestart += param._0.size;
        add(new Variable(param._0, param._1, cur));
      }
      cur += param._0.size;
    }
    return cur;
  }
  string mangleSelf() {
    if (extern_c || name == "main")
      return name;
    else
      return sup.mangle(name, type);
  }
  int framestart() {
    return _framestart;
  }
  string exit() { return mangleSelf() ~ "_exit_label"; }
  override {
    bool addsSelf() { return true; }
    string mangle(string name, IType type) {
      return mangleSelf() ~ "_" ~ name;
    }
    string getIdentifier() { return name; }
    void emitAsm(AsmFile af) {
      af.put(".globl "~mangleSelf);
      af.put(".type "~mangleSelf~", @function");
      af.put(mangleSelf() ~ ":"); // not really a label
      af.jump_barrier();
      af.pushStack("%ebp", voidp);
      af.mmove4("%esp", "%ebp");
      
      auto backup = af.currentStackDepth;
      scope(exit) af.currentStackDepth = backup;
      af.currentStackDepth = 0;
      
      withTLS(namespace, this, tree.emitAsm(af));
      af.emitLabel(exit());
      af.mmove4("%ebp", "%esp");
      af.popStack("%ebp", voidp);
      af.jump_barrier();
      af.put("ret");
    }
    Stuple!(IType, string, int)[] stackframe() {
      Stuple!(IType, string, int)[] res;
      foreach (obj; field)
        if (auto var = cast(Variable) obj._1)
          res ~= stuple(var.type, var.name, var.baseOffset);
      return res;
    }
  }
}

class FunCall : Expr {
  Expr[] params;
  Function fun;
  FunCall dup() {
    auto res = new FunCall;
    res.fun = fun;
    foreach (param; params) res.params ~= param.dup;
    return res;
  }
  mixin defaultIterate!(params);
  override void emitAsm(AsmFile af) {
    callFunction(af, fun.type.ret, params, fun.getPointer());
  }
  override string toString() { return Format("call(", fun, params, ")"); }
  override IType valueType() {
    return fun.type.ret;
  }
}

void handleReturn(IType ret, AsmFile dest) {
  if (Single!(Float) == ret) {
    dest.salloc(4);
    dest.floatStackDepth ++; // not locally produced
    dest.storeFloat("(%esp)");
    return;
  }
  if (!cast(Void) ret) {
    if (ret.size >= 8)
      dest.pushStack("%edx", Single!(SizeT));
    if (ret.size >= 12)
      dest.pushStack("%ecx", Single!(SizeT));
    if (ret.size == 16)
      dest.pushStack("%ebx", Single!(SizeT));
    dest.pushStack("%eax", Single!(SizeT));
  }
}

import tools.log;
void callFunction(AsmFile dest, IType ret, Expr[] params, Expr fp) {
  // dest.put("int $3");
  
  string name;
  if (auto s = cast(Symbol) fp) name = s.name;
  else name = "(nil)";
  
  assert(ret.size == 4 || ret.size == 8 || ret.size == 12 || ret.size == 16 || cast(Void) ret,
    Format("Return bug: ", ret, " from ", name, "!"));
  // TODO: backup FP stack
  dest.comment("Begin call to ", name);
  
  auto restore = dest.floatStackDepth;
  while (dest.floatStackDepth) dest.floatToStack();
  
  if (params.length) {
    foreach_reverse (param; params) {
      dest.comment("Push ", param);
      param.emitAsm(dest);
    }
  }
  fp.emitAsm(dest);
  dest.popStack("%eax", Single!(SizeT));
  dest.call("%eax");
  foreach (param; params) {
    dest.sfree(param.valueType().size);
  }
  
  while (restore--) {
    dest.stackToFloat();
    if (ret == Single!(Float))
      dest.swapFloats;
  }
  
  handleReturn(ret, dest);
}

class FunctionType : ast.types.Type {
  IType ret;
  Stuple!(IType, string)[] params;
  override int size() {
    asm { int 3; }
    assert(false);
  }
  override {
    string mangle() {
      string res = "function_to_"~ret.mangle();
      if (!params.length) return res;
      foreach (i, param; params) {
        if (!i) res ~= "_of_";
        else res ~= "_and_";
        res ~= param._0.mangle();
      }
      return res;
    }
    string toString() { return Format("Function of ", params, " => ", ret); }
  }
}

bool gotParlist(ref string str, ref Stuple!(IType, string)[] res, ParseCb rest) {
  auto t2 = str;
  IType ptype, lastType;
  string parname;
  if (t2.accept("(") &&
      t2.bjoin(
        ( // can omit types for subsequent parameters
          test(ptype = cast(IType) rest(t2, "type")) || test(ptype = lastType)
        ) && (t2.gotIdentifier(parname) || ((parname = null), true)),
        t2.accept(","),
        { lastType = ptype; res ~= stuple(ptype, parname); }
      ) &&
      t2.accept(")")
  ) {
    str = t2;
    return true;
  } else {
    return false;
  }
}

import parseBase;
// generalized to reuse for nested funs
Object gotGenericFun(T, bool Decl)(T fun, Namespace sup_override, bool addToNamespace,
                           ref string text, ParseCb cont, ParseCb rest) {
  IType ptype;
  auto t2 = text;
  New(fun.type);
  string parname;
  error = null;
  auto ns = namespace();
  assert(ns);
  if (test(fun.type.ret = cast(IType) rest(t2, "type")) &&
      t2.gotIdentifier(fun.name) &&
      t2.gotParlist(fun.type.params, rest)
    )
  {
    fun.fixup;
    auto backup = ns;
    scope(exit) namespace.set(backup);
    namespace.set(fun);
    if (addToNamespace) ns.add(fun);
    fun.sup = sup_override?sup_override:ns;
    text = t2;
    static if (Decl) {
      if (text.accept(";")) return fun;
      else throw new Exception("Expected ; at '"~t2.next_text()~"'");
    } else {
      if (rest(text, "tree.scope", &fun.tree)) return fun;
      else throw new Exception("Couldn't parse function scope at '"~text.next_text()~"'");
    }
  } else return null;
}

Object gotGenericFunDef(T)(T fun, Namespace sup_override, bool addToNamespace, ref string text, ParseCb cont, ParseCb rest) {
  return gotGenericFun!(T, false)(fun, sup_override, addToNamespace, text, cont, rest);
}
Object gotGenericFunDecl(T)(T fun, Namespace sup_override, bool addToNamespace, ref string text, ParseCb cont, ParseCb rest) {
  return gotGenericFun!(T, true)(fun, sup_override, addToNamespace, text, cont, rest);
}

Object gotFunDef(ref string text, ParseCb cont, ParseCb rest) {
  auto fun = new Function;
  return gotGenericFunDef(fun, cast(Namespace) null, true, text, cont, rest);
}
mixin DefaultParser!(gotFunDef, "tree.fundef");

// ensuing code gleefully copypasted from nestfun
// yes I wrote delegates first. how about that.
class FunctionPointer : ast.types.Type {
  IType ret;
  IType[] args;
  this() { }
  string toString() { return Format(ret, " function(", args, ")"); }
  this(IType ret, IType[] args) {
    this.ret = ret;
    this.args = args.dup;
  }
  this(Function fun) {
    ret = fun.type.ret;
    foreach (p; fun.type.params)
      args ~= p._0;
  }
  override int size() {
    return nativePtrSize;
  }
  override string mangle() {
    auto res = "fp_ret_"~ret.mangle()~"_args";
    if (!args.length) res ~= "_none";
    else foreach (arg; args)
      res ~= "_"~arg.mangle();
    return res;
  }
}

// &fun
class FunRefExpr : Expr, Literal {
  Function fun;
  this(Function fun) { this.fun = fun; }
  private this() { }
  mixin DefaultDup!();
  mixin defaultIterate!();
  override {
    IType valueType() {
      return new FunctionPointer(fun);
    }
    void emitAsm(AsmFile af) {
      (new Constant(fun.mangleSelf())).emitAsm(af);
    }
    string getValue() {
      return fun.mangleSelf();
    }
  }
}

Object gotFunRefExpr(ref string text, ParseCb cont, ParseCb rest) {
  auto t2 = text;
  if (!t2.accept("&")) return null;
  
  string ident;
  if (!t2.gotIdentifier(ident, true)) return null;
  auto fun = cast(Function) namespace().lookup(ident);
  // logln("fun is ", fun, " <- ", namespace().lookup(ident), " <- ", ident);
  if (!fun) return null;
  
  text = t2;
  
  return new FunRefExpr(fun);
}
mixin DefaultParser!(gotFunRefExpr, "tree.expr.fun_ref", "2101");

static this() {
  typeModlist ~= delegate IType(ref string text, IType cur, ParseCb, ParseCb rest) {
    IType ptype;
    Stuple!(IType, string)[] list;
    auto t2 = text;
    if (t2.accept("function") &&
      t2.gotParlist(list, rest)
    ) {
      text = t2;
      auto res = new FunctionPointer;
      res.ret = cur;
      foreach (entry; list) res.args ~= entry._0;
      return res;
    } else return null;
  };
}
