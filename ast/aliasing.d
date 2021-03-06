module ast.aliasing;

import ast.base, ast.parse, ast.structure, ast.namespace,
  tools.base: This, This_fn, rmSpace;

class ExprAlias : RelTransformable, Named, Expr {
  Expr base;
  string name;
  mixin MyThis!("base, name");
  mixin DefaultDup!();
  mixin defaultIterate!(base);
  override {
    string getIdentifier() { return name; }
    Object transform(Expr relbase) {
      void delegate(ref Iterable) dg;
      dg = (ref Iterable iter) {
        if (auto rt = cast(RelTransformable) iter)
          iter = fastcast!(Iterable)~ rt.transform(relbase);
        iter.iterate(dg);
      };
      auto it = fastcast!(Iterable)~ base.dup();
      dg(it);
      it.iterate(dg);
      return fastcast!(Object)~ it;
    }
    void emitAsm(AsmFile af) {
      fail; // Should never happen - the below foldopt should substitute them
      base.emitAsm(af); // may work .. or not.
    }
    IType valueType() { return base.valueType(); }
    string toString() {
      return Format("expr-alias ", name, "", " = ", base);
    }
  }
}

class CValueAlias : ExprAlias, CValue {
  mixin MyThis!("super(base, name)");
  override void emitLocation(AsmFile af) { (fastcast!(CValue)~ base).emitLocation(af); }
  override CValueAlias dup() { return new CValueAlias(base.dup, name); }
}

class LValueAlias : CValueAlias, LValue {
  mixin MyThis!("super(base, name)");
  override LValueAlias dup() { return new LValueAlias(base.dup, name); }
}

class MValueAlias : ExprAlias, MValue {
  mixin MyThis!("super(base, name)");
  override void emitAssignment(AsmFile af) { (fastcast!(MValue)~ base).emitAssignment(af); }
  override MValueAlias dup() { return new MValueAlias(base.dup, name); }
}

class TypeAlias : Named, IType, SelfAdding {
  IType base;
  bool strict;
  string name;
  mixin This!("base, name, strict = false");
  override {
    bool isComplete() { return base.isComplete; }
    bool addsSelf() { return true; }
    string getIdentifier() { return name; }
    bool isPointerLess() { return base.isPointerLess(); }
    int size() { return base.size; }
    string mangle() { return "type_alias_"~name.replace("-", "_dash_")~"_"~base.mangle; }
    ubyte[] initval() { return base.initval; }
    int opEquals(IType ty) {
      if (strict) {
        auto ta2 = fastcast!(TypeAlias) (ty);
        if (!ta2) return false;
        return base == ta2.base && name == ta2.name;
      }
      return base.opEquals(resolveType(ty));
    }
    IType proxyType() { if (strict) return null; return base; }
    string toString() { return Format(name, ":", base); }
  }
}

static this() {
  foldopt ~= delegate Itr(Itr it) {
    if (auto ea = fastcast!(ExprAlias) (it)) {
      return fastcast!(Iterable) (ea.base);
    } else return null;
  };
}

import ast.modules;
Object gotAlias(ref string text, ParseCb cont, ParseCb rest) {
  auto t2 = text;
  Expr ex;
  IType ty;
  Object obj;
  string id;
  bool notDone;
  
redo:
  bool strict;
  if (t2.accept("strict")) strict = true;
  if (!(t2.gotIdentifier(id) &&
        t2.accept("=")))
    t2.failparse("Couldn't parse alias");
  auto t3 = t2;
  bool gotTerm() {
    if (t3.accept(";")) return true;
    if (t3.accept(",")) {
      notDone = true;
      return true;
    }
    return false;
  }
  if (rest(t3, "type", &ty) && gotTerm()) {
    t2 = t3;
  } else {
    t3 = t2;
    ty = null;
    if (rest(t3, "tree.expr", &obj) && gotTerm()) {
      t2 = t3;
      if (auto e = fastcast!(Expr)~ obj) { obj = null; ex = e; }
      else {
        namespace().__add(id, obj); // for instance, function alias
      }
    } else
      t2.failparse("Couldn't parse alias target");
  }
  
  assert(ex || ty || obj);
  text = t2;
  auto cv = fastcast!(CValue)~ ex, mv = fastcast!(MValue)~ ex, lv = fastcast!(LValue)~ ex;
  if (ex) {
    if (strict) t2.failparse("no such thing as strict expr-alias");
    ExprAlias res;
    if (lv) res = new LValueAlias(lv, id);
    else if (mv) res = new MValueAlias(mv, id);
    else if (cv) res = new CValueAlias(cv, id);
    else res = new ExprAlias(ex, id);
    namespace().add(res);
  }
  if (ty) namespace().add(new TypeAlias(ty, id, strict));
  if (notDone) {
    notDone = false;
    goto redo;
  }
  return Single!(NamedNull);
}
mixin DefaultParser!(gotAlias, "struct_member.struct_alias", null, "alias");
mixin DefaultParser!(gotAlias, "tree.stmt.alias", "16", "alias");
mixin DefaultParser!(gotAlias, "tree.toplevel.alias", null, "alias");

import ast.casting;
static this() {
  // type alias implicitly casts to parent type
  implicits ~= delegate Expr(Expr ex) {
    auto ta = fastcast!(TypeAlias) (ex.valueType());
    if (!ta || !ta.strict) return null;
    return reinterpret_cast(ta.base, ex);
  };
}
