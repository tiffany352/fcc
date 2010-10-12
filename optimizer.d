module optimizer;

import assemble, tools.base, ast.base, ast.types;
alias asmfile.startsWith startsWith;

struct onceThenCall {
  void delegate(Transaction) dg;
  int opApply(int delegate(ref Transaction) _body) {
    Transaction tr;
    _body(tr);
    dg(tr);
    return 0;
  }
}

string opt(string name, string s) {
  string src = s.ctSlice("=>"), dest = s;
  string stmt_match = src.ctSlice(":");
  int instrs = 0;
  {
    string temp = stmt_match;
    while (temp.ctSlice(",").length) {
      src = src  .ctReplace("$"~ctToString(instrs), "match["~ctToString(instrs)~"]");
      dest = dest.ctReplace("$"~ctToString(instrs), "match["~ctToString(instrs)~"]");
      instrs ++;
    }
  }
  string res;
  res ~= `bool `~name~`(Transcache cache, ref int[string] labels_refcount) {
    bool changed;
    auto match = cache.findMatch("`~name~`", (Transaction[] list) {
      // logln("cond for `~name~`: ", list);
      if (list.length >= ` ~ ctToString(instrs);
  {
    string temp = stmt_match, merp; int i;
    while ((merp=temp.ctSlice(",")).length) {
      if (merp.ctStrip() == "*") i++;
      else
        res ~= ` && (` ~ merp.ctStrip().ctReplace("^", `list[` ~ ctToString(i++) ~ `].kind == Transaction.Kind.`) ~ `)`;
    }
  }
  res ~= `) {
        return ` ~ ctToString(instrs) ~ `;
      }
      else return 0;
    });
    if (match.length) _loophead:do {
      match.modded = false;`;
  if (src.ctStrip().length) res ~= `
      if (!(`~src~`)) continue;`;
  res ~= dest~`
      if (match.modded) {
        changed = true;
      }
    } while (match.advance());
    return changed;
  }
  opts ~= stuple(&`~name~`, "`~name~`", true);
  /* `~name~`();*/
  `;
  return res.ctReplace(
        "$SUBSTWITH", `foreach (ref $T res; onceThenCall(($T t) { match.replaceWith(t); })) with (res)`,
        "$SUBST", `match.replaceWith`,
        "$TK", `Transaction.Kind`,
        "$T", `Transaction`);
}

bool isRegister(string s) {
  return s.length > 2 && s[0] == '%' && s[1] != '(';
}

bool isLiteral(string s) {
  return s.length && s[0] == '$';
}

bool isNumLiteral(string s) {
  if (!s.isLiteral()) return false;
  foreach (ch; s[1 .. $])
    if (ch != '-' && (ch < '0' || ch > '9')) return false;
  return true;
}

int literalToInt(string s) {
  if (!isLiteral(s)) asm { int 3; }
  assert(isLiteral(s), "not a literal: "~s);
  return s[1 .. $].atoi();
}

bool referencesStack(ref Transaction t, bool affects = false) {
  bool foo(string s) { return s.find("%esp") != -1 || s.find("%ebp") != -1; }
  with (Transaction.Kind) switch (t.kind) {
    case   SAlloc, SFree            : return true;
    case                        Pop : if (affects) return true; return t.dest.foo();
    case                       Push : if (affects) return true; return t.source.foo();
    case                       Call : return true;
    case                        Mov : return t.from.foo() || t.to.foo();
    case                     MathOp : return t.op1.foo() || t.op2.foo();
    case                  FloatLoad : return t.source.foo();
    case       FloatPop, FloatStore : return t.dest.foo();
    case                  FloatMath : return false;
    default: break;
  }
  return true;
}

bool affectsStack(ref Transaction t) { return referencesStack(t, true); }

bool changesESP(ref Transaction t) {
  with (Transaction.Kind)
    return !!(t.kind == Push /or/ Pop);
}

bool hasSource(ref Transaction t) {
  with (Transaction.Kind)
    return !!(t.kind == Push /or/ FloatLoad);
}

bool hasDest(ref Transaction t) {
  with (Transaction.Kind)
    return !!(t.kind == Pop /or/ Call /or/ FloatStore /or/ FloatPop);
}

bool hasFrom(ref Transaction t) {
  with (Transaction.Kind)
    return !!(t.kind == Mov /or/ Mov2 /or/ Mov1);
}
alias hasFrom hasTo;

bool willOverwrite(ref Transaction t, string what) {
  if (!what.isRegister()) return false;
  if (hasDest(t)) return t.dest == what;
  if (hasTo(t)) return t.to == what;
  return false;
}

bool hasSize(ref Transaction t) {
  with (Transaction.Kind)
    return !!(t.kind == Push /or/ Pop /or/ Mov /or/ Mov2 /or/ Mov1);
}

int size(ref Transaction t) {
  with (Transaction.Kind) switch (t.kind) {
    case Push: return t.type.size;
    case Pop: return t.type.size;
    case Mov: return 4;
    case Mov2: return 2;
    case Mov1: return 1;
  }
  assert(false);
}

bool isMemRef(string s) {
  if (s.find("(") != -1) return true;
  if (s.startsWith("$")) return false;
  if (s == "%eax" /or/ "%ebx" /or/ "%ebp" /or/ "%ecx" /or/ "%edx") return false;
  if (s.startsWith("%gs:")) return true;
  return true;
}

// dg, name, allow
Stuple!(bool delegate(Transcache, ref int[string]), string, bool)[] opts;
bool optsSetup;

// track processor state
// obsoletes about a dozen peephole opts
class ProcTrack : ExtToken {
  string[string] known;
  string[] stack; // nativePtr-sized
  // in use by this set of transactions
  // emit before overwriting
  bool[string] use;
  // backup
  Transaction[] backup, knownGood;
  int overfree;
  string callDest;
  string toString() {
    return Format("cpu(", known, ", stack ", stack.length, "; ", stack, ", used ", use.keys, ")");
  }
  bool update(ref Transaction t) {
    scope(exit)
      if (isValid) {
        knownGood = translate();
        backup = null;
      }
    // #define .. lol
    const string Success = "{ backup ~= t; return true; }";
    string isIndirectSimple(string s) {
      if (s.length >= 2 && s[0] == '(' && s[$-1] == ')')
        return s[1..$-1];
      else return null;
    }
    string mkIndirect(string val) {
      if (val.startsWith("+(")) {
        auto op2 = val.between("(", ")"), op1 = op2.slice(",").strip();
        op2 = op2.strip();
        if (op1.isRegister() && op2.isNumLiteral()) {
          auto op2i = op2.literalToInt();
          if (t.to in use)
            return null;
          // to indirect access
          return Format(op2i, "(", op1, ")");
        }
      }
      return null;
    }
    void set(string mem, string val) {
      if (mem == val) known.remove(mem);
      else known[mem] = val;
    }
    if (callDest) return false;
    with (Transaction.Kind) switch (t.kind) {
      case Compare: return false;
      case MathOp:
        string op2 = t.op2;
        if (auto p = op2 in known) op2 = *p;
        
        if (t.op1.isLiteral() && t.op2 in known) {
          auto stuf = known[t.op2];
          if (stuf.isRegister())
            set(t.op2, "+(" ~ known[t.op2] ~ ", " ~ t.op1 ~ ")");
          else break;
          mixin(Success);
        }
        break;
      case SAlloc:
        if (overfree) return false;
        if (t.size == 4) {
          stack ~= null;
          mixin(Success);
        } else break;
      case SFree:
        if (t.size % nativePtrSize != 0) return false;
        for (int i = 0; i < t.size / nativePtrSize; ++i)
          if (stack.length) stack = stack[0 .. $-1];
          else overfree += nativePtrSize;
        mixin(Success);
      case Mov:
        if (t.to == "%esp")
          return false;
        if (t.from.startsWith("0("))
          t.from = t.from[1 .. $];
        
        if (t.from.find("%esp") != -1)
          return false; // TODO: can this ever be handled?
        if (t.from.isRegister()) {
          if (t.to in use) break; // lol
          string src = t.from;
          if (auto p = src in known)
            src = *p;
          if (src.isRegister())
            use[src] = true;
          if (t.to.isRegister()) {
            set(t.to, src);
          } else if (t.to == "(%esp)") {
            if (!stack.length) break;
            stack[$-1] = src;
          } else break;
          mixin(Success);
        } else if (auto deref = t.from.isIndirectSimple()) {
          if (deref in known) {
            auto val = known[deref];
            if (auto indir = mkIndirect(val)) {
              set(t.to, indir);
              mixin(Success);
            } else break;
          } else break;
        }
        break;
      case Label: return false;
      case Push:
        if (overfree) return false;
        if (t.source.isRegister() && t.type.size == nativePtrSize) {
          auto val = t.source;
          if (auto p = t.source in known)
            val = *p;
          if (val.isRegister()) use[val] = true;
          stack ~= val;
          mixin(Success);
        }
        if (t.source.isLiteral()) {
          if (t.type.size % nativePtrSize != 0)
            return false; // not a case we can handle
          auto steps = t.type.size / nativePtrSize;
          for (int i = 0; i < steps; ++i)
            stack ~= t.source;
          mixin(Success);
        }
        if (t.source in known && t.type.size == nativePtrSize) {
          stack ~= known[t.source];
          mixin(Success);
        }
        break;
      case Pop:
        if (!stack.length) break;
        if (t.type.size != nativePtrSize) return false;
        if (t.dest.isRegister()) {
          if (t.dest != stack[$-1] && t.dest in use) return false;
          set(t.dest, stack[$-1]);
          stack = stack[0 .. $-1];
          mixin(Success);
        }
        if (auto dest = t.dest.isIndirectSimple()) {
          if (dest in known) {
            if (auto indir = mkIndirect(known[dest])) {
              set(indir, stack[$-1]);
              stack = stack[0 .. $-1];
              mixin(Success);
            }
          }
          return false;
        }
        break;
      case Nevermind:
        if (t.dest in known) {
          known.remove(t.dest);
          mixin(Success);
        }
        break;
      case Call:
        auto dest = t.dest;
        if (auto rest = dest.startsWith("*")) {
          if (rest in known && known[rest].startsWith("$")) {
            callDest = known[rest][1..$];
            use[rest] = true;
            mixin(Success);
          }
        }
        return false;
      case Jump: return false;
      default: break;
    }
    return false;
    logln("---- Unsupported: ", t);
    logln("state ", this);
    assert(false);
  }
  bool isValid() {
    foreach (entry; stack) {
      if (entry.startsWith("+(")) return false;
      if (!entry.strip().length) return false;
    }
    foreach (mem, value; known) {
      if (value.startsWith("+(")) return false;
      // TODO: move over eax or something
      if (mem.isRelative() && value.isRelative()) return false;
    }
    return true;
  }
  Transaction[] translate() {
    if (!isValid()) return knownGood ~ backup;
    Transaction[] res;
    void addTransaction(Transaction.Kind tk, void delegate(ref Transaction) dg) {
      Transaction t;
      t.kind = tk;
      dg(t);
      res ~= t;
    }
    foreach (entry; stack) {
      addTransaction(Transaction.Kind.Push, (ref Transaction t) {
        t.source = entry;
        t.type = Single!(SysInt);
      });
    }
    foreach (reg, value; known) {
      addTransaction(Transaction.Kind.Mov, (ref Transaction t) {
        t.from = value; t.to = reg;
      });
    }
    if (overfree) {
      addTransaction(Transaction.Kind.SFree, (ref Transaction t) {
        t.size = overfree;
      });
    }
    if (callDest) {
      addTransaction(Transaction.Kind.Call, (ref Transaction t) {
        t.dest = callDest;
      });
    }
    return res;
  }
  string toAsm() { assert(false); }
}

bool delegate(Transcache, ref int[string]) ext_step;

void setupOpts() {
  if (optsSetup) return;
  optsSetup = true;
  bool goodMovSize(int i) { return i == 4 || i == 2 || i == 1; }
  static int xx;
  mixin(opt("ext_step", `*, *
    =>
    ProcTrack obj;
    $T t;
    t.kind = $TK.Extended;
    if ($0.kind == $TK.Extended) {
      obj = cast(ProcTrack) $0.obj;
      t.obj = obj;
      bool couldUpdate = obj.update($1);
      if (couldUpdate) {
        $SUBST([t]);
        if (match.to != match.parent.list.length) {
          goto skip; // > > > \
        } //                  v
      } //                    v
      auto res = obj./*       v */translate();
      if (!couldUpdate) res/* v */ ~= $1;
      $SUBST(res); //         v
      match.modded = false;// v meh. just skip one
      changed = true; //      v secretly
      skip:; //   < < < < < < /
    } else {
      New(obj);
      t.obj = obj;
      if (obj.update($0)) { $SUBST([t, $1]); }
    }
  `));
  .ext_step = &ext_step; // export
  opts = opts[0 .. $-1]; // only do ext_step once
  
  mixin(opt("rewrite_zero_ref", `*:
    hasSource($0) || hasDest($0) || hasFrom($0) || hasTo($0)
    =>
    auto t = $0;
    if (hasSource(t) && t.source.startsWith("0("))
      { t.source = t.source[1..$]; $SUBST([t]); }
    if (hasDest  (t) && t.dest  .startsWith("0("))
      { t.dest   = t.dest  [1..$]; $SUBST([t]); }
    if (hasFrom  (t) && t.from  .startsWith("0("))
      { t.from   = t.from  [1..$]; $SUBST([t]); }
    if (hasTo    (t) && t.to    .startsWith("0("))
      { t.to     = t.to    [1..$]; $SUBST([t]); }
  `));
  // alloc/free can be shuffled down past _anything_ that doesn't reference stack.
  mixin(opt("sort_mem", `^SAlloc || ^SFree, *:
    !affectsStack($1)
    =>
    int delta;
    if ($0.kind == $TK.SAlloc) delta = $0.size;
    else if ($0.kind == $TK.SFree) delta = -$0.size;
    else assert(false);
    auto t2 = $1;
    if (t2.hasStackdepth) t2.stackdepth -= delta;
    $SUBST([t2, $0]);
  `));
  mixin(opt("sort_pointless_mem", `^SAlloc || ^SFree, *:
    (hasSource($1) || hasDest($1) || hasFrom($1) || hasTo($1)) && !changesESP($1)
    =>
    string* sp;
    $T t = $1.dup;
    bool used;
    void doStuff(ref string s) {
      if (s.between("(", ")") != "%esp") return;
      auto offs = s.between("", "(").atoi();
      if ($0.kind == $TK.SAlloc) {
        if (offs > $0.size) { // will be unaffected
          s = Format(offs - $0.size, "(%esp)");
          used =  true;
        }
      } else {
        s = Format(offs + $0.size, "(%esp)");
        used = true;
      }
    }
    if (hasSource($1)) doStuff(t.source);
    if (hasDest  ($1)) doStuff(t.dest);
    if (hasFrom  ($1)) doStuff(t.from);
    if (hasTo    ($1)) doStuff(t.to);
    if (used)
      $SUBST([t, $0]);
  `));
  mixin(opt("collapse_alloc_frees", `^SAlloc || ^SFree, ^SAlloc || ^SFree =>
    int sum_inc;
    if ($0.kind == $TK.SAlloc) sum_inc += $0.size;
    else sum_inc -= $0.size;
    if ($1.kind == $TK.SAlloc) sum_inc += $1.size;
    else sum_inc -= $1.size;
    if (!sum_inc) $SUBST(null);
    else $SUBSTWITH {
      if (sum_inc > 0) kind = $TK.SAlloc;
      else kind = $TK.SFree;
      size = abs(sum_inc);
    }
  `));
  mixin(opt("collapse_alloc_free_nop", `^SAlloc || ^SFree => if (!$0.size) $SUBST(null); `));
  mixin(opt("pointless_free", `^SFree, ^Push:
    $0.size == $1.type.size && $0.size == 4 && !isMemRef($1.source) && $1.source != "%esp"
    =>
    $SUBSTWITH {
      kind = $TK.Mov;
      from = $1.source;
      to = "(%esp)";
    }
  `));
  mixin(opt("collapse_push_pop", `^Push, ^Pop:
    ($0.type.size == $1.type.size) && (!$0.source.isMemRef() || !$1.dest.isMemRef())
    =>
    if ($0.source == $1.dest) { /+logln("Who the fuck produced this retarded bytecode: ", match[]);+/ $SUBST(null); continue; }
    $T[] movs;
    int size = $0.type.size;
    string source = $0.source, dest = $1.dest;
    void incr(ref string s, int sz) {
      if (s.length && !s.startsWith("$") && !s.startsWith("%") && !s.startsWith("(")) {
        // num(reg)
        auto num = s.slice("(").atoi();
        s = Format(num + sz, "(", s);
        return;
      }
      if (s.length && s[0] == '$') { // number; repeat
        return;
      }
      logln(":: ", s, "; ", $0.source, " -> ", $1.dest);
      assert(false, "2");
    }
    void doMov($TK kind, int sz) {
      while (size >= sz) {
        $T mv;
        mv.kind = kind;
        mv.from = source; mv.to = dest;
        mv.stackdepth = $0.stackdepth;
        size -= sz;
        if (size) {
          source.incr(sz);
          dest.incr(sz);
        }
        movs ~= mv;
      }
    }
    doMov($TK.Mov, 4);
    doMov($TK.Mov2, 2);
    doMov($TK.Mov1, 1);
    $SUBST(movs);
  `));
  mixin(opt("add_mov", `^MathOp, ^Mov: $0.opName == "addl" && $0.op2 == "%eax" && $0.op2 == $1.from && $0.op1 == $1.to =>
    $SUBSTWITH {
      kind = $TK.MathOp;
      opName = $0.opName; op1 = "%eax"; op2 = $0.op1;
    }
  `));
  mixin(opt("fold_add_sub", `^MathOp, ^MathOp:
    $0.op2 == $1.op2 && $0.op1.isNumLiteral() && $1.op1.isNumLiteral()
    && $0.opName == "subl" && $1.opName == "addl"
    =>
    $SUBSTWITH {
      kind = $TK.MathOp;
      opName = "addl";
      op1 = Format("$", - $0.op1.literalToInt() + $1.op1.literalToInt());
      op2 = $0.op2;
    }
  `));
  mixin(opt("add_and_pop_reg", `^MathOp, ^Pop: $0.op2 == "(%esp)" && ($0.op1.find($1.to) == -1) =>
    auto res = $0.dup;
    res.op2 = $1.to;
    $SUBST([$1, res]);
  `));
  mixin(opt("fold_math", `^Mov, ^MathOp: $1.opName == "addl" && $0.to == $1.op2 && $0.from.isNumLiteral() && $1.op1.isNumLiteral() =>
    $SUBSTWITH {
      kind = $TK.Mov;
      from = Format("$", $0.from.literalToInt() + $1.op1.literalToInt());
      to = $0.to;
    }
  `));
  /// location access to a struct can be translated into an offset instruction
  mixin(opt("add_into_pop", `^MathOp, ^Pop:
    $0.opName == "addl" && $0.op1 == $1.dest &&
    $0.op2 == "(%esp)" && $1.type.size == 4
    =>
    $T t1 = $0, t2;
    swap(t1.op1, t1.op2);
    t2.kind = $TK.SFree;
    t2.size = 4;
    $SUBST([t1, t2]);
  `));
  mixin(opt("indirect_access_sub_fload", `^MathOp, ^FloatLoad:
    $0.opName == "subl" && $0.op1.isNumLiteral() && $0.op2 == "%eax"
    && $1.source.between("(", ")") == "%eax"
    =>
    $SUBSTWITH {
      kind = $1.kind;
      source = Format($1.source.between("", "(").atoi() - $0.op1.literalToInt(), "(%eax)");
    }
  `));
  mixin(opt("merge_literal_adds", `^MathOp, ^MathOp:
    $0.opName == "addl" && $1.opName == "addl" &&
    $0.op1.isNumLiteral() && $1.op1.isNumLiteral() &&
    $0.op2 == "%eax" && $1.op2 == "%eax"
    =>
    $SUBSTWITH {
      kind = $TK.MathOp;
      opName = "addl";
      op1 = Format("$", $0.op1.literalToInt() + $1.op1.literalToInt());
      op2 = "%eax";
    }
  `));
  mixin(opt("load_from_push", `^Push, ^FloatLoad:
    !$0.source.isRegister() && $1.source == "(%esp)"
    =>
    $T a1 = $1.dup, a2;
    a1.source = $0.source;
    if ($1.hasStackdepth) a1.stackdepth = $1.stackdepth - 4;
    a2.kind = $TK.SAlloc;
    a2.size = 4;
    $SUBST([a1, a2]);
  `));
  
  mixin(opt("fold_float_pop_load", `^FloatPop, ^FloatLoad, ^SFree: $0.dest == $1.source && $0.dest == "(%esp)" && $2.size == 4 => $SUBST([$2]);`));
  mixin(opt("fold_float_pop_load_to_store", `^FloatPop, ^FloatLoad: $0.dest == $1.source => $SUBSTWITH { kind = $TK.FloatStore; dest = $0.dest; }`));
  mixin(opt("make_call_direct", `^Mov, ^Call: $0.to == $1.dest => $SUBSTWITH { kind = $TK.Call; dest = $0.from; } `));
  mixin(opt("fold_mov_pop",  `^Mov, ^Pop : $0.from == $1.dest && $0.to == "(%esp)"
    =>
    $SUBSTWITH {
      kind = $TK.SFree;
      size = $1.type.size;
      assert(size == nativeIntSize, "3");
    }
  `));
  // some very special cases
  mixin(opt("float_meh_2",  `^FloatStore, ^FloatMath, ^FloatStore || ^FloatPop: $0.dest == $2.dest => $SUBST([$1, $2]); `));
  mixin(opt("float_meh_3",  `^FloatStore, ^FloatLoad, ^FloatMath, ^FloatStore: $0.dest != $1.source && $0.dest == $3.dest => $SUBST([$1, $2, $3]); `));
  mixin(opt("float_pointless_store",  `^FloatStore, ^FloatPop: $0.dest == $1.dest => $SUBST([$1]); `));
  
  // typical for delegates
  mixin(opt("indirect_access_2", `^Mov, ^MathOp, *:
    (hasDest($2) || hasSource($2)) &&
    $0.from.isRegister() && $1.opName == "addl" && $1.op1.isNumLiteral() &&
    $0.to == $1.op2 && $0.to == "%eax" && (hasDest($2) && $2.dest == "(%eax)" || hasSource($2) && $2.source == "(%eax)")
    =>
    $T t = $2;
    if (hasDest($2))
      t.dest  = Format($1.op1.literalToInt(), "(", $0.from, ")");
    else
      t.source = Format($1.op1.literalToInt(), "(", $0.from, ")");
    $SUBST([$0, $1, t]);
  `));
  mixin(opt("indirect_access_3", `^MathOp, *:
    hasSource($1) && $1.source == "(" ~ $0.op2 ~ ")" && $0.op1.isNumLiteral()
    && ($0.opName == "addl" /or/ "subl")
    =>
    auto t = $1;
    t.source = Format(($0.opName == "addl")?"":"-", $0.op1.literalToInt(), $1.source);
    $SUBST([t]);
  `));
  mixin(opt("ebp_to_esp", `*:
    (  hasSource($0) && $0.source.between("(", ")") == "%ebp"
    || hasDest  ($0) && $0.dest  .between("(", ")") == "%ebp"
    || hasFrom  ($0) && $0.from  .between("(", ")") == "%ebp"
    )
    && $0.hasStackdepth && (!hasSize($0) || size($0) != 1)
    =>
    $T t = $0;
    void doStuff(ref string str) {
      auto offs = str.between("", "(").atoi(); 
      auto new_offs = offs + t.stackdepth;
      if (new_offs) str = Format(new_offs, "(%esp)");
      else str = "(%esp)";
      $SUBST([t]);
    }
    bool skip;
    if ($0.kind == $TK.Push /or/ $TK.Pop) {
      // if we can't do the push in one step
      if ($0.type.size != 4 /or/ 2 /or/ 1) 
        skip = true;
    }
    if (!skip) {
      if (hasSource(t) && t.source.between("(", ")") == "%ebp") doStuff(t.source);
      if (hasDest  (t) && t.dest  .between("(", ")") == "%ebp") doStuff(t.dest);
      if (hasFrom  (t) && t.from  .between("(", ")") == "%ebp") doStuff(t.from);
      if (hasTo    (t) && t.to    .between("(", ")") == "%ebp") doStuff(t.to);
    }
  `));
  
  // jump opts
  mixin(opt("join_labels", `^Label, ^Label => auto t = $0; t.names = t.names ~ $1.names; $SUBST([t]); `));
  mixin(opt("pointless_jump", `^Jump, ^Label:
    $1.hasLabel($0.dest)
    =>
    labels_refcount[$0.dest] --;
    $SUBST([$1]);
  `));
}

// Stuple!(bool delegate(Transcache, ref int[string]), string, bool)[] opts;
// what's necessary to uniquely identify an opt
string unique(string s) {
  string res;
  int count() {
    int c;
    foreach (entry; opts)
      if (entry._1.startsWith(res)) c++;
    return c;
  }
  while (count > 1) {
    if (!s.length)
      return res; // give up
    res ~= s.take();
  }
  return res;
}
