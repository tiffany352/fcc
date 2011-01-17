module simplex;

import std.c.fenv, std.c.stdlib;

int[] perm;
vec3i[12] grad3;

float dot2(int[3] whee, float a, float b) {
  return whee[0] * a + whee[1] * b;
}

void permsetup() {
  perm ~= [for 0..256: rand() % 256].eval;
  perm ~= perm;
  int i;
  alias values = [1, 1, 0,
                 -1, 1, 0,
                  1,-1, 0,
                 -1,-1, 0,
                 
                  1, 0, 1,
                 -1, 0, 1,
                  1, 0,-1,
                 -1, 0,-1,
                 
                  0, 1, 1,
                  0,-1, 1,
                  0, 1,-1,
                  0,-1,-1];
  while ((int k, int l), int idx) ← zip (cross (0..12, 0..3), 0..-1) {
    grad3[k][l] = values[idx];
  }
}

float noise2(vec2f f) {
  if !perm.length permsetup;
  alias sqrt3 = sqrtf(3);
  alias f2 = 0.5 * (sqrt3 - 1);
  alias g2 = (3 - sqrt3) / 6;
  float[3] n = void;
  
  float s = (f.x + f.y) * f2;
  int i = fastfloor(f.x + s), j = fastfloor(f.y + s);
  
  float t = (i + j) * g2;
  vec2f[3] xy;
  xy[0] = f - (vec2i(i,j) - vec2f(t));
  
  int i1, j1;
  if xy[0].x > xy[0].y i1 = 1;
  else j1 = 1;
  
  {
    auto temp = 1 - 2 * g2;
    xy[1] = xy[0] - vec2i(i1, j1) + vec2f (g2);
    xy[2] = xy[0] - vec2f(temp);
  }
  int ii = i & 255, jj = j & 255;
  
  int[3] gi = void;
  gi[0] = perm[ii + perm[jj]] % 12;
  gi[1] = perm[ii + i1 + perm[jj + j1]] % 12;
  gi[2] = perm[ii + 1  + perm[jj + 1 ]] % 12;
  
  for (int k = 0; k < 3; ++k) {
    float ft = 0.5 - xy[k].x*xy[k].x - xy[k].y*xy[k].y;
    if ft < 0 n[k] = 0;
    else {
      ft = ft * ft;
      n[k] = ft * ft * dot2(grad3[gi[k]], xy[k]);
    }
  }
  return 0.5 + 35 * (n[0] + n[1] + n[2]);
}

double sumval;
int count;

void time-it(string t, void delegate() dg) {
  // calibrate
  int from1, to1, from2, to2;
  from1 = rdtsc[1];
  delegate void() { } ();
  to1 = rdtsc[1];
  // measure
  from2 = rdtsc[1];
  dg();
  to2 = rdtsc[1];
  auto delta = (to2 - from2) - (to1 - from1);
  if !count sumval = 0;
  sumval += delta; count += 1;
  writeln "$t: $delta, average $(sumval / count)";
}

float noise3(vec3f v) {
  vec3f[4] vs = void;
  float s = void, t = void;
  int i = void, j = void, k = void;
  int[4] gi = void;
  int mask = void;
  vec3f v0 = void;
  vec3i offs1 = void, offs2 = void;
  int ii = void, jj = void, kk = void;
  auto pair = [0f, 1f];
  float sum = 0f;
  int id = void, id2 = void, id3 = void, c = void;
  vec3f forble = void;
  if !perm.length permsetup;
  
  s = (v.x + v.y + v.z) / 3.0f;
  i = fastfloor(v.x + s); j = fastfloor(v.y + s); k = fastfloor(v.z + s);
  t = (i + j + k) / 6.0f;
  vs[0] = v - vec3i(i, j, k) + vec3f(t);
  vs[1] = vs[0]            + vec3f(1.0f / 6);
  vs[2] = vs[0]            + vec3f(2.0f / 6);
  vs[3] = vs[0] - vec3f(1) + vec3f(3.0f / 6);
  v0 = vs[0];
  if (v0.x >= v0.y) {
    if (v0.y >= v0.z) {
      mask = 0b100_110;
    } else if (v0.x >= v0.z) {
      mask = 0b100_101;
    } else {
      mask = 0b001_101;
    }
  } else {
    if (v0.y < v0.z) {
      mask = 0b001_011;
    } else if (v0.x < v0.z) {
      mask = 0b010_011;
    } else {
      mask = 0b010_110;
    }
  }
  offs1 = vec3i((mask >> 5)    , (mask >> 4) & 1, (mask >> 3) & 1);
  offs2 = vec3i((mask >> 2) & 1, (mask >> 1) & 1, (mask >> 0) & 1);
  // prevent costly fildl
  vs[1] = vs[1] - vec3f(pair[offs1.x], pair[offs1.y], pair[offs1.z]);
  vs[2] = vs[2] - vec3f(pair[offs2.x], pair[offs2.y], pair[offs2.z]);
  ii = i & 255; jj = j & 255; kk = k & 255;
  alias i1 = offs1.x, i2 = offs2.x,
        j1 = offs1.y, j2 = offs2.y,
        k1 = offs1.z, k2 = offs2.z;
  gi[0] = perm[ii+perm[jj+perm[kk]]] % 12;
  gi[1] = perm[ii+i1+perm[jj+j1+perm[kk+k1]]] % 12;
  gi[2] = perm[ii+i2+perm[jj+j2+perm[kk+k2]]] % 12;
  gi[3] = perm[ii+1+perm[jj+1+perm[kk+1]]] % 12;
  while (c <- 0..4) {
    auto q = vs[c];
    auto ft = 0.6f - q.lensq;
    if (ft >= 0) {
      id = gi[c]; id2 = id & 3; id3 = id & 12;
      ft *= ft;
      forble = vec3f(1f - [0f, 2f][id2&1], 1f - [0f, 2f][(id2&2) >> 1], 0f);
      if (id3 == 4) forble = forble.xzy;
      if (id3 == 8) forble = forble.zxy;
      sum += ft * ft * (forble*q).sum;
    }
  }
  return 0.5f + 16.0f*sum;
}