select /*+ recompile ordered use_nl */ count (a.c1)
from t80 a, t80 b
where a.c1 = b.c1;
