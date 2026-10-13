select /*+ recompile ordered use_merge */ count (*)
from t40 a, t40 b
where a.c1 = b.c1;
