select /*+ recompile ordered use_nl */ count (*)
from t60 a, t60 b
where a.c1 = b.c1;
