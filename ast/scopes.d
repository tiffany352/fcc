module ast.scopes;

import ast.base, ast.namespace, ast.variable, parseBase, tools.base: apply;

class Mew : LineNumberedStatementClass {
	LineNumberedStatement dup() { assert(false); }
	void iterate(void delegate(ref Iterable), IterMode mode = IterMode.Lexical) { assert(false); }
}

import ast.aggregate;
class Scope : Namespace, ScopeLike, LineNumberedStatement {
	Mew lnsc; // "multiple inheritance" hack
  Statement _body;
  Statement[] guards;
  int[] guard_offsets;
  ulong id;
  bool needEntryLabel;
  int pad_framesize;
  int requiredDepth; // sanity checking
  string requiredDepthDebug;
  static int scope_count;
  int count;
  mixin defaultIterate!(_body, guards);
  override void configPosition(string str) {
		lnsc.configPosition(str);
  }
  override void getInfo(ref string n, ref int l) { lnsc.getInfo(n, l); }
  Statement[] getGuards() {
    if (auto sl = fastcast!(ScopeLike) (sup)) return sl.getGuards() ~ guards;
    else return guards;
  }
  int[] getGuardOffsets() {
    if (auto sl = fastcast!(ScopeLike) (sup)) return sl.getGuardOffsets() ~ guard_offsets;
    else return guard_offsets;
  }
  void addStatement(Statement st) {
    if (auto as = fastcast!(AggrStatement) (_body)) as.stmts ~= st;
    else if (!_body) _body = st;
    else {
      auto as = new AggrStatement;
      as.stmts ~= _body;
      as.stmts ~= st;
      _body = as;
    }
  }
  void addGuard(Statement st) {
    guards ~= st;
    guard_offsets ~= namespace().get!(ScopeLike).framesize();
  }
  void addStatementToFront(Statement st) {
    if (auto as = fastcast!(AggrStatement) (_body)) as.stmts = st ~ as.stmts;
    else if (!_body) _body = st;
    else {
      auto as = new AggrStatement;
      as.stmts ~= st;
      as.stmts ~= _body;
      _body = as;
    }
  }
  string entry() { return Format(".L", id, "_entry"); }
  string exit() { return Format(".L", id, "_exit"); }
  string toString() { return Format("scope(", framesize(), ") <- ", sup); }
  this() {
    count = scope_count ++;
    // if (count == 3951) fail;
    id = getuid();
    sup = namespace();
    New(lnsc);
    recalcRequiredDepth;
  }
  void recalcRequiredDepth() {
    requiredDepth = framesize();
    if (requiredDepth == -1) {
      requiredDepth = int.max;
    }
    requiredDepthDebug = Format(this);
  }
  void setSup(Namespace ns) {
    sup = ns;
    recalcRequiredDepth;
  }
  override Scope dup() {
    auto backup = namespace();
    scope(exit) namespace.set(backup);
    namespace.set(sup);
    
    auto res = new Scope;
    res.field = field.dup;
    if (_body) res._body = _body.dup;
    foreach (guard; guards) res.guards ~= guard.dup;
    res.guard_offsets = guard_offsets.dup;
    res.id = getuid();
    res.lnsc = lnsc;
    res.requiredDepth = requiredDepth;
    res.requiredDepthDebug = "[dup]"~requiredDepthDebug;
    return res;
  }
  override int framesize() {
    int res;
    if (auto sl = fastcast!(ScopeLike)~ sup) {
      auto supsz = sl.framesize();
      if (supsz == -1) return -1;
      res += supsz;
    }
    foreach (obj; field) {
      if (auto var = fastcast!(Variable)~ obj._1) {
        res += getFillerFor(var.type, res);
        res += var.type.size;
      }
    }
    res += pad_framesize;
    if (isARM) {
      while (res % 4 != 0) res ++;
    }
    return res;
  }
  // frame offset caused by parameters
  int framestart() {
    return get!(FrameRoot).framestart();
  }
  bool emitted;
  // continuations good
  void delegate(bool=false) delegate() open(AsmFile af) {
    lnsc.emitAsm(af);
    // logln(lnsc.name, ":", lnsc.line, ": start ", this);
    if (emitted) {
      logln("double emit scope. ");
      fail;
    }
    emitted = true;
    if (needEntryLabel) af.emitLabel(entry(), !keepRegs, !isForward);
    auto checkpt = af.checkptStack(), backup = namespace();
    namespace.set(this);
    // sanity checking
    if (requiredDepth != int.max && af.currentStackDepth != requiredDepth) {
      logln("Scope emit failure: expected stack depth ", requiredDepth, ", but got ", af.currentStackDepth);
      logln("was: ", requiredDepthDebug);
      logln(" is: ", this);
      logln("mew: ", _body);
      fail;
    }
    return stuple(checkpt, backup, this, af) /apply/ (typeof(checkpt) checkpt, typeof(backup) backup, typeof(this) that, AsmFile af) {
      if (that._body) {
        that._body.emitAsm(af);
      }
      return stuple(checkpt, that, backup, af) /apply/ (typeof(checkpt) checkpt, typeof(that) that, typeof(backup) backup, AsmFile af, bool onlyCleanup) {
        if (!onlyCleanup) af.emitLabel(that.exit(), !keepRegs, isForward);
        
        foreach_reverse(i, guard; that.guards) {
          af.restoreCheckptStack(that.guard_offsets[i]);
          guard.emitAsm(af);
        }
        
        af.restoreCheckptStack(checkpt);
        if (!onlyCleanup) namespace.set(backup);
      };
    };
  }
  override {
    void emitAsm(AsmFile af) {
      open(af)()(); // lol
    }
    Object lookup(string name, bool local = false) {
      auto res = super.lookup(name, true);
      // TODO: &&? ||? WHO KNOWS =D
      // if (!res && fastcast!(Scope)~ sup)
      if (res) return res;
      return sup.lookup(name, local);
    }
    string mangle(string name, IType type) {
      // fail;
      return sup.mangle(name, type) ~ "_local";
    }
    Stuple!(IType, string, int)[] stackframe() {
      typeof(sup.stackframe()) res;
      if (sup) res = sup.stackframe();
      foreach (obj; field)
        if (auto var = fastcast!(Variable)~ obj._1)
          res ~= stuple(var.type, var.name, var.baseOffset);
      return res;
    }
  }
  int frame_end() { int res; foreach (entry; stackframe()) { res = min(res, entry._2); } return res; }
}

Object gotScope(ref string text, ParseCb cont, ParseCb rest) {
  if (auto res = rest(text, "tree.stmt.aggregate")) return res; // always scope anyway
  auto sc = new Scope;
  sc.configPosition(text);
  namespace.set(sc);
  scope(exit) namespace.set(sc.sup);
  auto t2 = text;
  Statement _body;
  if (rest(t2, "tree.stmt", &_body)) { text = t2; sc.addStatement(_body); return sc; }
  t2.failparse("Couldn't match scope");
}
mixin DefaultParser!(gotScope, "tree.scope");
