select
	/*+ recompile */
	(
		select
			nvl(sum(vote), 0) 
		from
			tbl2 
		where
			tbl2.id like tbl1.id || '%'
	) 
from
	tbl1;
