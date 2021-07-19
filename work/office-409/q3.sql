select
	/*+ recompile */
	1
from
	tbl2 
where
	tbl2.id like tbl2.id || '%'
