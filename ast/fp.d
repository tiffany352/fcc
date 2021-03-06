module ast.fp;

import parseBase, ast.base, ast.types, ast.literals;

Object gotFloatProperty(ref string text, ParseCb cont, ParseCb rest) {
  auto t2 = text;
  if (t2.accept("infinity")) { text = t2; return new FloatExpr(float.infinity); }
  if (t2.accept("nan")) { text = t2; return new FloatExpr(float.nan); }
  if (t2.accept("epsilon")) { text = t2; return new FloatExpr(float.epsilon); }
  return null;
}
mixin DefaultParser!(gotFloatProperty, "tree.expr.fprop", "24048", "float.");
