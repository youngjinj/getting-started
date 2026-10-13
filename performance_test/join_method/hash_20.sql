select /*+ recompile ordered use_hash */ count (a.c1)
from t20 a, t20 b
where a.c1 = b.c1;
