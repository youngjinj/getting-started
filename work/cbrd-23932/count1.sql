SELECT
	host_id,
	avg_cpu_used_rto
FROM
	foo
WHERE
	log_ocr_ymdt BETWEEN '2011-02-21 13:45:00'
	AND '2011-02-21 13:45:59'
	AND host_id IN ('00:30:48:5C:9E:28', '00:24:E8:7A:A3:4B');
