DROP TABLE IF EXISTS T1;	
CREATE TABLE T1 (C1 INT, C2 INT);

INSERT INTO T1 VALUES (1, 1), (1, 2);

MERGE INTO T1 A USING (
        SELECT
                C1,
		C2
        FROM
                T1
) B ON (
        A.C1 = B.C1
)
WHEN MATCHED THEN
UPDATE
SET
        A.C2 = B.C2;
