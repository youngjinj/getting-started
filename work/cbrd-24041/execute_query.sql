set optimization level 513;

select
    /*+ recompile */
    count(*)
from
    tab_a a,
    v1 b
where
    a.col1 = b.col1
    and b.col2 = 1;
