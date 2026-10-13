select /*+ recompile ordered use_hash */ count (a.c1)
from t60 a, t60 b
where a.c1 = b.c1;
