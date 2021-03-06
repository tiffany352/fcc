module ast.literal_string;

import ast.base, ast.literals, ast.pointer, ast.arrays, ast.static_arrays, ast.stringparse;

static int string_counter;

class StringExpr : Expr, HasInfo, Dependency {
  string str;
  this() { }
  this(string s) { str = s; this(); }
  mixin defaultIterate!();
  string name_used;
  void selectName(AsmFile af) {
    if (!name_used) {
      name_used = af.allocConstant(Format("string_constant_", string_counter ++), cast(ubyte[]) str);
    }
  }
  Expr getPointer() {
    return reinterpret_cast(Single!(Pointer, Single!(Char)), new LateSymbol(&selectName, &name_used)); 
  }
  override {
    string getInfo() { return "'"~toString()[1 .. $-1]~"'"; }
    StringExpr dup() { return new StringExpr(str); }
    string toString() { return '"'~str.replace("\n", "\\n")~'"'; }
    // default action: place in string segment, load address on stack
    void emitAsm(AsmFile af) {
      // if (name_used == "string_constant_232") fail;
      getPointer().emitAsm(af);
      (mkInt(str.length)).emitAsm(af);
    }
    void emitDependency(AsmFile af) {
      selectName(af);
      af.allocConstant(name_used, cast(ubyte[]) str, true);
      af.markWeak(name_used);
    }
    // IType valueType() { return new StaticArray(Single!(Char), str.length); }
    IType valueType() { return Single!(Array, Single!(Char)); }
  }
}

static this() {
  mkString = delegate Expr(string s) { return new StringExpr(s); };
}

Object gotStringLiteralExpr(ref string text, ParseCb cont, ParseCb rest) {
  // "" handled in ast.stringex now.
  string st;
  if (text.gotString(st, "`", true)) {
    return new StringExpr(st);
  } else return null;
}
mixin DefaultParser!(gotStringLiteralExpr, "tree.expr.literal_string", "551", "`");

import ast.casting, ast.fold;
static this() {
  implicits ~= delegate Expr(Expr ex) {
    if (resolveType(ex.valueType()) != Single!(Array, Single!(Char)))
      return null;
    if (fastcast!(StringExpr) (foldex(ex))) {
      return getArrayPtr(ex);
    }
    return null;
  };
  implicits ~= delegate Expr(Expr ex) {
    if (resolveType(ex.valueType()) != Single!(Array, Single!(Char)))
      return null;
    if (auto str = fastcast!(StringExpr) (foldex(ex))) {
      if (str.str.length == 1)
        return reinterpret_cast(Single!(Char), new DataExpr(cast(ubyte[]) str.str));
    }
    return null;
  };
  implicits ~= delegate Expr(Expr ex) {
    if (resolveType(ex.valueType()) != Single!(Char))
      return null;
    return reinterpret_cast(Single!(Byte), ex);
  };
}
