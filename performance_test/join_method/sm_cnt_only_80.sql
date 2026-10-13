select /*+ recompile ordered use_merge */ count (*)
from t80 a, t80 b
where a.c1 = b.c1;
