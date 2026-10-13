select /*+ recompile ordered use_nl */ count (a.c1)
from t100 a, t100 b
where a.c1 = b.c1;
