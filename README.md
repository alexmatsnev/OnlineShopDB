Учебный проект базы данных PostgreSQL для небольшого онлайн магазина.





Index benchmarking (queries/05\_index\_benchmarks.sql)



Index: idx\_orders\_order\_date



Query 1: One month of orders

EXPLAIN (ANALYZE, BUFFERS)

SELECT \* FROM orders

WHERE order\_date >= '2026-05-01 00:00+05'

&#x20; AND order\_date <  '2026-06-01 00:00+05';



BEGIN;

DROP INDEX idx\_orders\_order\_date;

EXPLAIN (ANALYZE, BUFFERS)

SELECT \* FROM orders

WHERE order\_date >= '2026-05-01 00:00+05'

&#x20; AND order\_date <  '2026-06-01 00:00+05';

ROLLBACK;



Query 2: 10 latest orders

EXPLAIN (ANALYZE, BUFFERS)

SELECT \* FROM orders

ORDER BY order\_date DESC

LIMIT 10;



BEGIN;

DROP INDEX idx\_orders\_order\_date;

EXPLAIN (ANALYZE, BUFFERS)

SELECT \* FROM orders

ORDER BY order\_date DESC

LIMIT 10;

ROLLBACK;



Results:

Query	               Time With / Without     Speedup    Pages read With / Without

One month of orders    0.110 ms  / 0.431 ms    \~4×        97 / 94

10 latest orders       0.028 ms  / 0.410 ms    \~15×       12 / 94



Index: uq\_customers\_email\_lower



Query: lower(email) lookup

EXPLAIN (ANALYZE, BUFFERS)

SELECT \* FROM customers

WHERE lower(email) = lower('Customer500@Example.com');



BEGIN;

DROP INDEX uq\_customers\_email\_lower;

EXPLAIN (ANALYZE, BUFFERS)

SELECT \* FROM customers

WHERE lower(email) = lower('Customer500@Example.com');

ROLLBACK;



Results:

Query	               Time With / Without     Speedup    Pages read With / Without

lower(email) lookup    0.035 ms  / 0.305 ms    \~9×        3 / 29



Script output:



ANALYZE

ANALYZE

CREATE FUNCTION



=== 1.1 One month of orders: WITH idx\_orders\_order\_date ===

&#x20;                                                                          QUERY PLAN                                   

\----------------------------------------------------------------------------------------------------------------------------------------------------------------

&#x20;Bitmap Heap Scan on orders  (cost=17.37..118.81 rows=496 width=44) (actual time=0.048..0.136 rows=483.00 loops=1)

&#x20;  Recheck Cond: ((order\_date >= '2026-05-01 00:00:00+05'::timestamp with time zone) AND (order\_date < '2026-06-01 00:00:00+05'::timestamp with time zone))

&#x20;  Heap Blocks: exact=94

&#x20;  Buffers: shared hit=97

&#x20;  ->  Bitmap Index Scan on idx\_orders\_order\_date  (cost=0.00..17.25 rows=496 width=0) (actual time=0.033..0.033 rows=483.00 loops=1)

&#x20;        Index Cond: ((order\_date >= '2026-05-01 00:00:00+05'::timestamp with time zone) AND (order\_date < '2026-06-01 00:00:00+05'::timestamp with time zone))

&#x20;        Index Searches: 1

&#x20;        Buffers: shared hit=3

&#x20;Planning:

&#x20;  Buffers: shared hit=26

&#x20;Planning Time: 0.170 ms

&#x20;Execution Time: 0.159 ms

(12 rows)





=== 1.1 One month of orders: WITHOUT the index ===

BEGIN

DROP INDEX

&#x20;                                                                     QUERY PLAN                                        

\------------------------------------------------------------------------------------------------------------------------------------------------------

&#x20;Seq Scan on orders  (cost=0.00..244.22 rows=496 width=44) (actual time=0.009..0.454 rows=483.00 loops=1)

&#x20;  Filter: ((order\_date >= '2026-05-01 00:00:00+05'::timestamp with time zone) AND (order\_date < '2026-06-01 00:00:00+05'::timestamp with time zone))

&#x20;  Rows Removed by Filter: 9532

&#x20;  Buffers: shared hit=94

&#x20;Planning:

&#x20;  Buffers: shared hit=5

&#x20;Planning Time: 0.106 ms

&#x20;Execution Time: 0.474 ms

(8 rows)





ROLLBACK



=== 1.2 Ten latest orders: WITH idx\_orders\_order\_date ===

&#x20;                                                                      QUERY PLAN                                       

\--------------------------------------------------------------------------------------------------------------------------------------------------------

&#x20;Limit  (cost=0.29..1.03 rows=10 width=44) (actual time=0.009..0.016 rows=10.00 loops=1)

&#x20;  Buffers: shared hit=12

&#x20;  ->  Index Scan Backward using idx\_orders\_order\_date on orders  (cost=0.29..746.51 rows=10015 width=44) (actual time=0.008..0.014 rows=10.00 loops=1)

&#x20;        Index Searches: 1

&#x20;        Buffers: shared hit=12

&#x20;Planning:

&#x20;  Buffers: shared hit=38

&#x20;Planning Time: 0.189 ms

&#x20;Execution Time: 0.025 ms

(9 rows)





=== 1.2 Ten latest orders: WITHOUT the index ===

BEGIN

DROP INDEX

&#x20;                                                       QUERY PLAN                                                      

\--------------------------------------------------------------------------------------------------------------------------

&#x20;Limit  (cost=410.57..410.60 rows=10 width=44) (actual time=0.782..0.783 rows=10.00 loops=1)

&#x20;  Buffers: shared hit=94

&#x20;  ->  Sort  (cost=410.57..435.61 rows=10015 width=44) (actual time=0.781..0.782 rows=10.00 loops=1)

&#x20;        Sort Key: order\_date DESC

&#x20;        Sort Method: top-N heapsort  Memory: 26kB

&#x20;        Buffers: shared hit=94

&#x20;        ->  Seq Scan on orders  (cost=0.00..194.15 rows=10015 width=44) (actual time=0.007..0.321 rows=10015.00 loops=1)

&#x20;              Buffers: shared hit=94

&#x20;Planning:

&#x20;  Buffers: shared hit=5

&#x20;Planning Time: 0.107 ms

&#x20;Execution Time: 0.795 ms

(12 rows)





ROLLBACK



=== 1.3 Case-insensitive email lookup: WITH uq\_customers\_email\_lower ===

&#x20;                                                              QUERY PLAN                                               

\----------------------------------------------------------------------------------------------------------------------------------------

&#x20;Index Scan using uq\_customers\_email\_lower on customers  (cost=0.28..8.29 rows=1 width=85) (actual time=0.022..0.022 rows=1.00 loops=1)

&#x20;  Index Cond: (lower((email)::text) = 'customer500@example.com'::text)

&#x20;  Index Searches: 1

&#x20;  Buffers: shared hit=3

&#x20;Planning:

&#x20;  Buffers: shared hit=43

&#x20;Planning Time: 0.134 ms

&#x20;Execution Time: 0.033 ms

(8 rows)





=== 1.3 Case-insensitive email lookup: WITHOUT the index ===

BEGIN

DROP INDEX

&#x20;                                              QUERY PLAN

\--------------------------------------------------------------------------------------------------------

&#x20;Seq Scan on customers  (cost=0.00..44.15 rows=5 width=85) (actual time=0.165..0.302 rows=1.00 loops=1)

&#x20;  Filter: (lower((email)::text) = 'customer500@example.com'::text)

&#x20;  Rows Removed by Filter: 1009

&#x20;  Buffers: shared hit=29

&#x20;Planning:

&#x20;  Buffers: shared hit=5

&#x20;Planning Time: 0.115 ms

&#x20;Execution Time: 0.311 ms

(8 rows)





ROLLBACK



=== 1.4 Exact email lookup (no lower): cannot use the lower(email) index ===

&#x20;                                              QUERY PLAN

\--------------------------------------------------------------------------------------------------------

&#x20;Seq Scan on customers  (cost=0.00..41.62 rows=1 width=85) (actual time=0.047..0.080 rows=1.00 loops=1)

&#x20;  Filter: ((email)::text = 'customer500@example.com'::text)

&#x20;  Rows Removed by Filter: 1009

&#x20;  Buffers: shared hit=29

&#x20;Planning:

&#x20;  Buffers: shared hit=17

&#x20;Planning Time: 0.156 ms

&#x20;Execution Time: 0.091 ms

(8 rows)







=== 2. Average execution time (200 runs each) ===

psql:queries/05\_index\_benchmarks.sql:139: NOTICE:  order\_date one month    | with index                    0.102  ms per run  (200 runs)

psql:queries/05\_index\_benchmarks.sql:139: NOTICE:  order\_date latest 10    | with index                    0.032  ms per run  (200 runs)

psql:queries/05\_index\_benchmarks.sql:139: NOTICE:  lower(email) lookup     | with index                    0.036  ms per run  (200 runs)

DO

BEGIN

DROP INDEX

psql:queries/05\_index\_benchmarks.sql:152: NOTICE:  order\_date one month    | WITHOUT index                 0.455  ms per run  (200 runs)

psql:queries/05\_index\_benchmarks.sql:152: NOTICE:  order\_date latest 10    | WITHOUT index                 0.429  ms per run  (200 runs)

DO

ROLLBACK

BEGIN

DROP INDEX

psql:queries/05\_index\_benchmarks.sql:162: NOTICE:  lower(email) lookup     | WITHOUT index                 0.313  ms per run  (200 runs)

DO

ROLLBACK



=== 3. Inserting 5 000 orders ===

BEGIN

psql:queries/05\_index\_benchmarks.sql:188: NOTICE:  insert 5 000 orders      | with indexes                  41.3  ms

DO

ROLLBACK

BEGIN

DROP INDEX

DROP INDEX

psql:queries/05\_index\_benchmarks.sql:206: NOTICE:  insert 5 000 orders      | WITHOUT 2 indexes             35.9  ms

DO

ROLLBACK



Done. Nothing was changed: all index drops and inserts were rolled back.

