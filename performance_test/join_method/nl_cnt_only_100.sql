select /*+ recompile ordered use_nl */ count (*)
from t100 a, t100 b
where a.c1 = b.c1;
