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
}

class Void : Type {
  override {
    int size() { return 1; }
    string mangle() { return "void"; }
    ubyte[] initval() { return null; }
    string toString() { return "void"; }
  }
}

class Variadic : Type {
  override int size() { assert(false); }
  /// BAH
  // TODO: redesign parameter match system to account for automatic conversions in variadics.
  override string mangle() { return "variadic"; }
  override ubyte[] initval() { assert(false, "Cannot declare variadic variable. "); } // wtf variadic variable?
}

class Char : Type {
  override int size() { return 1; }
  override string mangle() { return "char"; }
  override bool isPointerLess() { return true; }
}

class Byte : Type {
  override int size() { return 1; }
  override string mangle() { return "byte"; }
  override bool isPointerLess() { return true; }
}

const nativeIntSize = 4, nativePtrSize = 4;

class SizeT : Type {
  override int size() { return nativeIntSize; }
  override string mangle() { return "size_t"; }
  override bool isPointerLess() { return true; }
}

class Short : Type {
  override int size() { return 2; }
  override string mangle() { return "short"; }
  override bool isPointerLess() { return true; }
}

class SysInt : Type {
  override int size() { return nativeIntSize; }
  override string mangle() { return "sys_int"; }
  override bool isPointerLess() { return true; }
}

class Long : Type {
  override int size() { return 8; }
  override string mangle() { return "long"; }
  override bool isPointerLess() { return true; }
}

class Float : Type {
  override int size() { return 4; }
  override string mangle() { return "float"; }
  override bool isPointerLess() { return true; }
}

class Double : Type {
  override int size() { return 8; }
  override string mangle() { return "double"; }
  override bool isPointerLess() { return true; }
}

class Real : Type {
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

import parseBase;
Object gotBasicType(ref string text, ParseCb cont, ParseCb rest) {
  if (text.accept("void")) return Single!(Void);
  if (text.accept("size_t")) return Single!(SizeT);
  if (text.accept("int")) return Single!(SysInt);
  if (text.accept("long")) return Single!(Long);
  if (text.accept("short")) return Single!(Short);
  if (text.accept("char")) return Single!(Char);
  if (text.accept("byte")) return Single!(Byte);
  if (text.accept("float")) return Single!(Float);
  if (text.accept("double")) return Single!(Double);
  if (text.accept("real")) return Single!(Real);
  if (text.accept("...")) return Single!(Variadic);
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
