module std.random.base;

interface IRandom {
  void init(int seed);
  int rand();
}

// producer, quality
(IRandom delegate(int), IRandom delegate(IRandom), int)[] engines;

IRandom getPRNG(int s) {
  int best; IRandom delegate(int) res;
  for auto tup <- engines
    if tup[2] > best (res, best) = tup[(0, 2)];
  return res s;
}

IRandom getPRNG(IRandom ir) {
  int best; IRandom delegate(IRandom) res;
  for auto tup <- engines
    if tup[2] > best (res, best) = tup[(1, 2)];
  return res ir;
}