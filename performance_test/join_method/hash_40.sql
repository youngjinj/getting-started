select /*+ recompile ordered use_hash */ count (a.c1)
from t40 a, t40 b
where a.c1 = b.c1;
