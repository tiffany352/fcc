module ast.structure;

import ast.types, ast.base, ast.namespace, parseBase;

import tools.base: ex;
int sum(S, T)(S s, T t) {
  int res;
  foreach (entry; s)
    res += t(entry);
  return res;
}

class Structure : Type {
  string name;
  struct Member {
    string name;
    Type type;
  }
  Member[] members;
  int lookupMember(string name) {
    foreach (i, m; members) if (m.name == name) return i;
    throw new Exception(Format(name, " is not a member of ", this.name, "!"));
  }
  int getMemberOffset(int id) {
    int offs;
    foreach (member; members[0 .. id]) offs += member.type.size;
    return offs;
  }
  override int size() {
    return members.sum(ex!("t -> t.type.size()"));
  }
  this(string name, Member[] members) {
    this.name = name;
    this.members = members;
  }
  override string mangle() { return "struct_"~name; }
}

Object gotStructDef(ref string text, ParseCb cont, ParseCb rest) {
  auto t2 = text;
  if (!t2.accept("struct ")) return null;
  string name;
  Structure.Member[] ms;
  Structure.Member sm;
  if (t2.gotIdentifier(name) && t2.accept("{") &&
      t2.many(
        test(sm.type = cast(Type) rest(t2, "type")) &&
        t2.bjoin(
          t2.gotIdentifier(sm.name),
          t2.accept(",")
          ,{ ms ~= sm; }
        ) &&
        t2.accept(";")
      ) &&
      t2.accept("}")
    )
  {
    text = t2;
    auto st = new Structure(name, ms);
    namespace().add(st);
    return Single!(NoOp);
  } else return null;
}
mixin DefaultParser!(gotStructDef, "tree.typedef.struct");

import ast.pointer;
class MemberAccess(T) : T {
  T base;
  int which;
  this(T t, string name) { base = t; which = (cast(Structure) base.valueType()).lookupMember(name); }
  override {
    Type valueType() {
      return (cast(Structure) base.valueType()).members[which].type;
    }
    void emitAsm(AsmFile af) {
      auto st = cast(Structure) base.valueType();
      static if (is(T: LValue)) {
        assert(st.members[which].type.size == 4);
        base.emitLocation(af);
        af.popStack("%eax", new Pointer(st));
        af.mmove4(Format(st.getMemberOffset(which), "(%eax)"), "%eax");
        af.pushStack("%eax", st.members[which].type);
      } else {
        assert(st.members[which].type.size == 4);
        base.emitAsm(af);
        af.mmove4(Format(st.getMemberOffset(which), "(%esp)"), "%eax");
        af.sfree(st.size);
        af.pushStack("%eax", st.members[which].type);
      }
    }
    static if (is(T: LValue)) {
      void emitLocation(AsmFile af) {
        base.emitLocation(af);
        af.mathOp("addl", Format("$", (cast(Structure) base.valueType()).getMemberOffset(which)), "(%esp)");
      }
    }
  }
}

alias MemberAccess!(Expr) MemberAccess_Expr;
alias MemberAccess!(LValue) MemberAccess_LValue;

import ast.parse;
Object gotMemberExpr(ref string text, ParseCb cont, ParseCb rest) {
  auto t2 = text;
  
  assert(lhs_partial());
  auto ex = cast(Expr) lhs_partial();
  if (!ex) return null;
  
  string member;
  
  auto pre_ex = ex;
  if (t2.accept(".") && t2.gotIdentifier(member)) {
    if (!cast(Structure) ex.valueType())
      throw new Exception(Format("Can't access member of non-structure: ", ex, " at ", t2.next_text()));
    
    if (auto lv = cast(LValue) ex)
      ex = new MemberAccess_LValue(lv, member);
    else
      ex = new MemberAccess_Expr(ex, member);
    text = t2;
    return cast(Object) ex;
  } else return null;
}
mixin DefaultParser!(gotMemberExpr, "tree.rhs_partial.access_member");

Object gotStructName(ref string text, ParseCb cont, ParseCb rest) {
  string id, t2 = text;
  if (t2.gotIdentifier(id)) {
    if (auto st = cast(Structure) namespace().lookup(id)) {
      text = t2;
      return st;
    }
  }
  return null;
}
mixin DefaultParser!(gotStructName, "type.struct", "4");