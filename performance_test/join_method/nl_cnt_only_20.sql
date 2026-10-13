select /*+ recompile ordered use_nl */ count (*)
from t20 a, t20 b
where a.c1 = b.c1;
