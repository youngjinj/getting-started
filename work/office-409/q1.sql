select
	/*+ recompile */
	(
		select
			nvl(sum(vote), 0) 
		from
			tbl2 
		where
			tbl2.id like substr(tbl1.id, 1, 3) || '%'
	) 
from
	tbl1;
