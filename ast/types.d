module ast.types;

import tools.base: Stuple, take;

import casts;

interface IType {
  int size();
  string mangle();
  ubyte[] initval();
  int opEquals(IType);
  // return the type we are a proxy for, or null
  // (proxy == type alias)
  IType proxyType();
  bool isPointerLess(); // concerns the VALUE ITSELF - ie. an array is always pointerful
  bool isComplete(); // is this type completely defined or does it depend on future stuff?
}

// Strips out type-alias and the like
IType resolveType(IType t) {
  while (t) {
    if (auto tp = t.proxyType()) {
      t = tp;
      continue;
    }
    break;
  }
  return t;
}

template TypeDefaults(bool INITVAL = true, bool OPEQUALS = true) {
  static if (INITVAL) ubyte[] initval() { return new ubyte[size()]; }
  static if (OPEQUALS) {
    int opEquals(IType ty) {
      // specialize where needed
      ty = resolveType(ty);
      auto obj = cast(Object) (cast(void*) (ty) - (***cast(Interface***) ty).offset);
      return
        (this.classinfo is obj.classinfo)
        &&
        (size == (cast(typeof(this)) cast(void*) obj).size);
    }
  }
  IType proxyType() { return null; }
}

class Type : IType {
  mixin TypeDefaults!();
  abstract int size();
  abstract string mangle();
  bool isPointerLess() { return false; } // default
  bool isComplete() { return true; } // also default
  string toString() { return mangle(); }
}

final class Void : Type {
  override {
    int size() { return 1; }
    string mangle() { return "void"; }
    ubyte[] initval() { return null; }
    string toString() { return "void"; }
  }
}

final class Variadic : Type {
  override int size() { assert(false); }
  /// BAH
  // TODO: redesign parameter match system to account for automatic conversions in variadics.
  override string mangle() { return "variadic"; }
  override ubyte[] initval() { assert(false, "Cannot declare variadic variable. "); } // wtf variadic variable?
}

final class Char : Type {
  override int size() { return 1; }
  override string mangle() { return "char"; }
  override bool isPointerLess() { return true; }
}

final class Byte : Type {
  override int size() { return 1; }
  override string mangle() { return "byte"; }
  override bool isPointerLess() { return true; }
}

const nativeIntSize = 4, nativePtrSize = 4;

final class SizeT : Type {
  override int size() { return nativeIntSize; }
  override string mangle() { return "size_t"; }
  override bool isPointerLess() { return true; }
}

final class Short : Type {
  override int size() { return 2; }
  override string mangle() { return "short"; }
  override bool isPointerLess() { return true; }
}

final class SysInt : Type {
  override int size() { return nativeIntSize; }
  override string mangle() { return "int"; }
  override bool isPointerLess() { return true; }
}

final class Long : Type {
  override int size() { return 8; }
  override string mangle() { return "long"; }
  override bool isPointerLess() { return true; }
}

final class Float : Type {
  override int size() { return 4; }
  override string mangle() { return "float"; }
  override bool isPointerLess() { return true; }
}

final class Double : Type {
  override int size() { return 8; }
  override string mangle() { return "double"; }
  override bool isPointerLess() { return true; }
}

final class Real : Type {
  override int size() { return 10; }
  override string mangle() { return "real"; }
  override bool isPointerLess() { return true; }
}

// quick and dirty singleton
template _Single(T, U...) {
  T value;
  static this() { value = new T(U); }
}

template Single(T, U...) {
  static assert(is(T: Object));
  alias _Single!(T, U).value Single;
}

const string BasicTypeTable = `
  name   | type
  void   | Void
  size_t | SizeT
  int    | SysInt
  long   | Long
  short  | Short
  char   | Char
  byte   | Byte
  float  | Float
  double | Double
  real   | Real
  ...    | Variadic
`;

import parseBase, tools.ctfe: ctTableUnroll;
Object gotBasicType(ref string text, ParseCb cont, ParseCb rest) {
  mixin(BasicTypeTable.ctTableUnroll(`
    if (text.accept("$name")) return Single!($type);
  `));
  return null;
}
mixin DefaultParser!(gotBasicType, "type.basic", "3");

// postfix type modifiers
IType delegate(ref string text, IType cur, ParseCb cont, ParseCb rest)[]
  typeModlist;

Object gotExtType(ref string text, ParseCb cont, ParseCb rest) {
  auto type = fastcast!(IType)~ cont(text);
  if (!type) return null;
  restart:
  foreach (dg; typeModlist) {
    if (auto nt = dg(text, type, cont, rest)) {
      type = nt;
      goto restart;
    }
  }
  return fastcast!(Object)~ type;
}
mixin DefaultParser!(gotExtType, "type.ext", "1");
