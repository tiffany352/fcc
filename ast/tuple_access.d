module ast.tuple_access;

import ast.base, ast.tuples, ast.structure, ast.scopes;

Expr mkTupleIndexAccess(Expr tuple, int pos) {
  if (auto rt = fastcast!(RefTuple) (tuple)) {
    return rt.mvs[pos];
  }
  auto wrapped = (fastcast!(Tuple)~ tuple.valueType()).wrapped;
  
  MemberAccess_Expr res;
  if (fastcast!(LValue)~ tuple) res = new MemberAccess_LValue;
  else res = new MemberAccess_Expr;
  res.base = reinterpret_cast(wrapped, tuple);
  
  auto temps = wrapped.selectMap!(RelMember, "$");
  if (pos >= temps.length) { logln("index access length violation: ", pos, " > ", temps.length, " for ", tuple); fail; }
  res.stm = temps[pos];
  
  auto types = (fastcast!(Tuple)~ tuple.valueType()).types();
  return reinterpret_cast(types[pos], res);
}

import ast.modules;
Expr[] getTupleEntries(Expr tuple, Statement* initst = null, bool dontLvize = false) {
  auto tt = fastcast!(Tuple)~ tuple.valueType();
  if (!tt) return null;
  auto count = tt.types.length;
  if (count) {
    Expr mkcheap(Expr ex, Statement* late_init = null) {
      bool isCheap(Expr ex) { // cheap to flatten
        return _is_cheap(ex, CheapMode.Flatten);
      }
      if (dontLvize || isCheap(ex)) return ex;
      if (late_init) {
        Statement st2; Expr ex2;
        if (auto sam = fastcast!(StatementAndMValue) (ex)) {
          st2 = sam.first;
          ex2 = sam.second;
        }
        if (auto sal = fastcast!(StatementAndLValue) (ex)) {
          st2 = sal.first;
          ex2 = sal.second;
        }
        if (auto sae = fastcast!(StatementAndExpr) (ex)) {
          st2 = sae.first;
          ex2 = sae.second;
        }
        if (st2 && ex2) {
          if (isCheap(ex2)) {
            *late_init = st2;
            return ex2;
          }
        }
      }
      if (!namespace()) {
        fail;
      }
      if (namespace().get!(EmittingContext).isBeingEmat) {
        logln("Too late to change stackframe via tmpizing!");
        fail;
      }
      // force allocation
      ex = tmpize_if_possible(ex, late_init);
      return ex;
    }
    if (!initst) {
      tuple = mkcheap(tuple);
    } else {
      Statement st;
      tuple = mkcheap(tuple, &st);
      if (st) *initst = st;
    }
  }
  Expr[] res;
  for (int i = 0; i < count; ++i)
    res ~= mkTupleIndexAccess(tuple, i);
  return res;
}

import ast.parse, ast.fold, ast.int_literal, ast.namespace, ast.opers;
static this() {
  defineOp("index", delegate Expr(Expr e1, Expr e2) {
    Tuple tup;
    if (!gotImplicitCast(e1, (IType it) {
      tup = fastcast!(Tuple) (it);
      return tup && tup.types.length != 1; // resolve ambiguity with array index
    }))
      return null;
    int count;
    tup.wrapped.select((string, RelMember rm) { count ++; }, &tup.wrapped.rmcache);
    /// 2.1
    if (!gotImplicitCast(e2, (IType it) { return test(Single!(SysInt) == it); }))
      return null;
    e2 = foldex(e2);
    auto ie = fastcast!(IntExpr) (e2);
    if (!ie) {
      return null;
      // throw new Exception(Format(e2, " could not be simplified to an int in tuple index access"));
    }
    if (ie.num < 0 || ie.num !< count)
      throw new Exception(Format(ie.num, " out of bounds for tuple access"));
    return fastcast!(Expr) (mkTupleIndexAccess(e1, ie.num));
  });
  defineOp("length", delegate Expr(Expr ex) {
    Tuple tup;
    if (!gotImplicitCast(ex, (IType it) {
      tup = fastcast!(Tuple) (it);
      return tup && tup.types.length != 1; // resolve ambiguity with array length
    }))
      return null;
    return mkInt(tup.types.length);
  });
}

import ast.iterator, ast.casting;
static this() {
  defineOp("index", delegate Expr(Expr e1, Expr e2) {
    auto tup = fastcast!(Tuple) (resolveType(e1.valueType()));
    if (!tup) return null;
    int count;
    tup.wrapped.select((string, RelMember rm) { count ++; }, &tup.wrapped.rmcache);
    /// 2.1
    if (count <= 1) return null;
    if (!gotImplicitCast(e2, (IType it) { return test(fastcast!(RangeIsh) (it)); }))
      return null;
    
    auto rish = fastcast!(RangeIsh) (e2.valueType()),
      from = rish.getPos(e2),
      to   = rish.getEnd(e2);
    auto ifrom = fastcast!(IntExpr) (fold(from)), ito = fastcast!(IntExpr) (fold(to));
    if (!ifrom || !ito) fail("fail");
    auto start = tup.wrapped.selectMember(ifrom.num).offset;
    if (ifrom.num == ito.num) {
      return mkTupleExpr();
    }
    auto restype = mkTuple(tup.wrapped.slice(ifrom.num, ito.num).types);
    auto res = iparse!(Expr, "tuple_slice", "tree.expr")
                      (`*restype*:(void*:&lv + base)`,
                       "restype", restype, "lv", fastcast!(LValue)~ e1,
                       "base", mkInt(start));
    return res;
  });
}

class WithSpace : Namespace {
  Object[] spaces;
  Expr pureValue;
  Expr[] values;
  this(Expr ex) {
    sup = namespace();
    spaces ~= fastcast!(Object) (ex.valueType());
    values ~= ex;
  }
  this(Object[] spaces, Expr pureValue, Expr[] values) {
    sup = namespace();
    this.spaces = spaces;
    this.pureValue = pureValue;
    this.values = values;
  }
  override {
    string mangle(string name, IType type) { assert(false); }
    Stuple!(IType, string, int)[] stackframe() { assert(false); }
    Object lookup(string name, bool local = false) {
      if (name == "that") {
        if (!pureValue) throw new Exception("Oops. ");
        return fastcast!(Object) (pureValue);
      }
      foreach (i, space; spaces) {
        auto rns = fastcast!(RelNamespace) (space);
        
        if (!rns) 
          if (auto srns = fastcast!(SemiRelNamespace) (space))
            rns = srns.resolve();
        
        if (auto srns = fastcast!(SemiRelNamespace) (rns))
          rns = srns.resolve();
        
        if (rns)
          if (auto res = rns.lookupRel(name, values[i])) return res;
        
        if (auto ns = fastcast!(Namespace) (space))
          if (auto res = ns.lookup(name, local)) return res;
      }
      return sup.lookup(name, local);
    }
  }
}

import ast.iterator, ast.casting, ast.pointer, ast.vardecl, ast.conditionals;
Object gotWithTupleExpr(ref string text, ParseCb cont, ParseCb rest) {
  return lhs_partial.using = delegate Object(Object obj) {
    {
      auto t2 = text;
      if (!t2.accept("(")) return null;
    }
    auto ex = fastcast!(Expr) (obj);
    Statement initLv;
    if (ex) {
      if (fastcast!(Variable) (ex)) {
        // I guess we don't need to do anything in this case.
      } else if (auto lv = fastcast!(LValue) (ex)) {
        ex = new DerefExpr(lvize(new RefExpr(lv), &initLv));
      } else {
        ex = lvize(ex, &initLv);
        ex = new RCE(ex.valueType(), ex, true); // make sure it's treated as an expr!
      }
      while (fastcast!(Pointer) (resolveType(ex.valueType())))
        ex = new DerefExpr(ex);
    }
    
    Object fixup(Object obj) {
      if (!initLv) return obj;
      if (auto cd = fastcast!(Cond) (obj))
        return new StatementAndCond(initLv, cd);
      if (auto ex = fastcast!(Expr) (obj)) {
        // // TODO: fix function call tuple flattening so this is feasible again
        return fastcast!(Object) (mkStatementAndExpr(initLv, ex));
        // namespace().get!(Scope).addStatement(initLv);
        // return fastcast!(Object) (ex);
      }
      logln("cannot fixup: unknown ", obj);
      fail;
    }
    
    if (auto it = fastcast!(IType) (obj))
      obj = fastcast!(Object) (resolveType(it));
    
    Object[] spaces;
    Expr[] values;
    
    if (ex) {
      auto outer_ex = ex;
      gotImplicitCast(ex, (Expr ex) {
        auto it = ex.valueType();
        if (fastcast!(Namespace) (it) || fastcast!(RelNamespace) (it) || fastcast!(SemiRelNamespace) (it)) {
          spaces ~= fastcast!(Object) (it);
          values ~= ex;
        }
        return false;
      });
    } else {
      if (auto ns = fastcast!(Namespace) (obj)) {
        spaces ~= obj; values ~= null;
      } else if (auto rn = fastcast!(RelNamespace) (obj)) {
        spaces ~= obj; values ~= null;
      }
    }
    
    if (!spaces.length)
      if (ex)
        text.failparse("Not a [rel]namespace: type ", ex.valueType());
      else
        text.failparse("Not a [rel]namespace: obj ", obj.classinfo.name, ": ", obj);
    
    auto backup = namespace();
    scope(exit) namespace.set(backup);
    namespace.set(new WithSpace(spaces, ex, values));
    
    Object res;
    if (!rest(text, "tree.expr _tree.expr.arith", &res) && !rest(text, "cond", &res))
      text.failparse("Couldn't get with-tuple expr");
    /*if (auto rt = fastcast!(RefTuple) (res)) if (rt.mvs.length == 1) {
      auto lv2mv = fastcast!(LValueAsMValue) (rt.mvs[0]);
      if (lv2mv) return fixup(fastcast!(Object) (lv2mv.sup));
      return fixup(fastcast!(Object) (rt.mvs[0]));
    }*/
    return fixup(res);
  };
}
mixin DefaultParser!(gotWithTupleExpr, "tree.rhs_partial.withtuple", null, ".");

static this() {
  /// 3.
  implicits ~= delegate void(Expr ex, void delegate(Expr) dg) {
    while (true) {
      auto tup = fastcast!(Tuple) (resolveType(ex.valueType()));
      if (!tup) return;
      if (tup.types.length != 1) return;
      if (tup !is ex.valueType()) ex = reinterpret_cast(tup, ex);
      ex = mkTupleIndexAccess(ex, 0);
      dg(ex);
    }
  };
  // cast into tuples
  implicits ~= delegate void(Expr ex, IType it, void delegate(Expr) dg) {
    if (!it || !fastcast!(Tuple) (it)) return;
    if (auto tup = fastcast!(Tuple)~ ex.valueType()) {
      if ((fastcast!(Tuple)~ it).types.length != tup.types.length)
        return;
      Statement initst;
      auto exprs = getTupleEntries(ex, &initst);
      Expr[] stack;
      Expr[][] casts;
      foreach (entry; exprs) {
        stack ~= entry;
        casts ~= getAllImplicitCasts(entry);
      }
      auto offs = new int[exprs.length];
      int inc(int i) {
        stack[i] = casts[i][offs[i]++];
        if (offs[i] == casts[i].length) offs[i] = 0;
        return offs[i];
      }
      while (true) {
        int i;
        while (i < exprs.length && !inc(i)) i++;
        if (i == exprs.length) break;
        auto t = mkTupleExpr(stack);
        if (initst) t = mkStatementAndExpr(initst, t);
        if (it == t.valueType()) dg(t);
      }
    }
  };
}
