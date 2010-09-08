module ast.tuple_access;

import ast.base, ast.tuples, ast.structure;

Expr mkTupleIndexAccess(Expr tuple, int pos) {
  auto wrapped = (cast(Tuple) tuple.valueType()).wrapped;
  RelMember[] temps;
  wrapped.select((string, RelMember rm) { temps ~= rm; });
  if (auto lv = cast(LValue) tuple) {
    auto ma = new MemberAccess_LValue;
    ma.base = new RCL(wrapped, lv);
    ma.stm = temps[pos];
    return ma;
  } else {
    auto ma = new MemberAccess_Expr;
    ma.base = new RCE(wrapped, tuple);
    ma.stm = temps[pos];
    return ma;
  }
}

Expr[] getTupleEntries(Expr tuple) {
  auto tt = cast(Tuple) tuple.valueType();
  assert(tt);
  auto count = tt.types.length;
  Expr[] res;
  for (int i = 0; i < count; ++i)
    res ~= mkTupleIndexAccess(tuple, i);
  return res;
}

import ast.parse, ast.fold, ast.int_literal, ast.namespace;
Object gotTupleIndexAccess(ref string text, ParseCb cont, ParseCb rest) {
  return lhs_partial.using = delegate Object(Expr ex) {
    auto tup = cast(Tuple) ex.valueType();
    if (!tup) return null;
    int count;
    tup.wrapped.select((string, RelMember rm) { count ++; });
    /// 2.1
    if (count <= 1) return null; // resolve ambiguity with array index
    auto t2 = text;
    Expr index;
    if (
      !t2.accept("[") ||
      !rest(t2, "tree.expr", &index) ||
      !gotImplicitCast(index, (IType it) { return test(Single!(SysInt) == it); }) ||
      !t2.accept("]")) return null;
    text = t2;
    index = fold(index);
    auto ie = cast(IntExpr) index;
    if (!ie) {
      throw new Exception(Format(index, " could not be simplified to an int in tuple index access at '"~text.next_text()~"'. "));
    }
    if (ie.num < 0 || ie.num !< count)
      throw new Exception(Format(ie.num, " out of bounds for tuple access at '"~text.next_text()~"'. "));
    return cast(Object) mkTupleIndexAccess(ex, ie.num);
  };
}
mixin DefaultParser!(gotTupleIndexAccess, "tree.rhs_partial.tuple_index_access");

import ast.iterator, ast.casting;
Object gotTupleSliceExpr(ref string text, ParseCb cont, ParseCb rest) {
  return lhs_partial.using = delegate Object(Expr ex) {
    auto tup = cast(Tuple) ex.valueType();
    if (!tup) return null;
    int count;
    tup.wrapped.select((string, RelMember rm) { count ++; });
    /// 2.1
    if (count <= 1) return null;
    auto t2 = text;
    Expr range;
    if (!t2.accept("[") ||
        !rest(t2, "tree.expr", &range) ||
        !gotImplicitCast(range, (IType it) { return test(cast(Range) it); }) ||
        !t2.accept("]")) return null;
    auto
      ex2 = new RCE((cast(Range) range.valueType()).wrapper, range),
      from = iparse!(Expr, "range_from", "tree.expr")("ex2.cur", "ex2", ex2),
      to   = iparse!(Expr, "range_to",   "tree.expr")("ex2.end", "ex2", ex2);
    text = t2;
    auto ifrom = cast(IntExpr) fold(from), ito = cast(IntExpr) fold(to);
    assert(ifrom && ito);
    auto start = tup.wrapped.selectMember(ifrom.num).offset;
    auto restype = mkTuple(tup.wrapped.slice(ifrom.num, ito.num).types);
    auto res = iparse!(Expr, "tuple_slice", "tree.expr")
                      (`*cast(restype*) (cast(void*) &lv + base)`,
                       "restype", restype, "lv", cast(LValue) ex,
                       "base", new IntExpr(start));
    return cast(Object) res;
  };
}
mixin DefaultParser!(gotTupleSliceExpr, "tree.rhs_partial.tuple_slice");

static this() {
  /// 3.
  implicits ~= delegate Expr(Expr ex) {
    auto tup = cast(Tuple) ex.valueType();
    if (!tup) return null;
    if (!tup.size) return null;
    return fold(mkTupleIndexAccess(ex, 0));
  };
}