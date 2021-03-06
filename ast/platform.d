module ast.platform;

import ast.base, parseBase, ast.fun, ast.namespace, ast.pointer, ast.stringparse, ast.scopes;

import ast.modules;
Object gotPlatform(bool Stmt)(ref string text, ParseCb cont, ParseCb rest) {
  auto t2 = text;
  string platname;
  bool neg, wild;
  if (!t2.accept("(")) return null;
  if (t2.accept("!")) neg = true;
  if (!t2.gotIdentifier(platname))
    t2.failparse("Invalid platform identifier");
  if (t2.accept("*")) wild = true;
  if (!t2.accept(")"))
    t2.failparse("expected closing paren");
  t2.noMoreHeredoc();
  auto src = t2.coarseLexScope(true, false);
  auto ns = namespace(), mod = fastcast!(Module) (current_module());
  if (platname == "x86") platname = "default";
  bool match = platname~"-" == platform_prefix || platname == "default" && !platform_prefix;
  if (wild) match |= !!platform_prefix.startsWith(platname);
  if (neg) match = !match;
  if (match) {
    Object obj;
    if (!src.many(
        !!rest(src, Stmt?"tree.stmt":"tree.toplevel", &obj),
        {
          static if (Stmt) {
            if (auto st = fastcast!(Statement) (obj)) {
              auto sc = fastcast!(Scope) (ns);
              if (!sc) fail;
              sc.addStatement(st);
            }
          } else {
            if (auto n = fastcast!(Named) (obj))
              if (!addsSelf(obj))
                ns.add(n);
            if (auto tr = fastcast!(Tree) (obj)) mod.entries ~= tr;
          }
        }
      ))
      src.failparse("Failed to parse platform body. ");
    src.eatComments();
    if (src.mystripl().length) {
      src.failparse("Unknown statement. ");
    }
  }
  text = t2;
  return Single!(NoOp);
}
mixin DefaultParser!(gotPlatform!(false), "tree.toplevel.platform", null, "platform");
mixin DefaultParser!(gotPlatform!(true), "tree.stmt.platform", "311", "platform");
