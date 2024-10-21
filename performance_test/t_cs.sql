select /*+ recompile use_idx */ count (*)
from t1 a, t1 b
where a.c1 = b.c1 and b.c2 = 0;
