module ast.variable;

import ast.base, ast.opers, ast.literals, parseBase, ast.casting, ast.static_arrays: DataExpr;

import tools.log;
class Variable : LValue, Named {
  string address() { return Format(baseOffset, "(%ebp)"); }
  override {
    void emitAsm(AsmFile af) {
      mixin(mustOffset("type.size"));
      if (isARM) {
        if (type.size == 4) {
          af.mmove4(qformat("[fp, #", baseOffset, "]"), "r0");
          af.pushStack("r0", 4);
        } else {
          armpush(af, "fp", type.size, baseOffset);
        }
      } else {
        af.pushStack(address, type.size);
      }
    }
    void emitLocation(AsmFile af) {
      lookupOp("+", new Register!("ebp"), mkInt(baseOffset)).emitAsm(af);
    }
    IType valueType() {
      return type;
    }
  }
  IType type;
  string name;
  // offset off ebp
  int baseOffset;
  bool dontInit;
  Expr initval;
  void initInit() {
    if (initval) return;
    else {
      initval = reinterpret_cast(
        valueType(),
        new DataExpr(type.initval())
      );
    }
  }
  this() { }
  this(IType t, string s, int i) {
    type = t;
    name = s;
    baseOffset = i;
    initInit();
  }
  this(IType t, string s, Expr ex, int i) {
    this(t, s, i);
    initval = ex;
  }
  override string getIdentifier() { return name; }
  mixin DefaultDup!();
  mixin defaultIterate!();
  string toString() {
    if (name) return name;
    return Format("[ var of ", type, " at ", baseOffset, "]");
  }
}
