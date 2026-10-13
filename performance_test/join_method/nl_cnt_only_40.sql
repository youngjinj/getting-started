select /*+ recompile ordered use_nl */ count (*)
from t40 a, t40 b
where a.c1 = b.c1;
