select /*+ recompile use_idx */ b.c2
from t1 a, t2 b
where a.c1 = b.c1;
