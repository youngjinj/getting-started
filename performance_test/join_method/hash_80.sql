select /*+ recompile ordered use_hash */ count (a.c1)
from t80 a, t80 b
where a.c1 = b.c1;
