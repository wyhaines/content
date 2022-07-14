# Counting (with PostgreSQL and MySQL/InnoDB) is Slow

Counting records in a database table seems like it should be a simple task. Naively, one might assume that, given that the database sofware is responsible for inserting and removing records from a table, it should just know how many records there are in the table. Thus, shouldn't counting always be fast?

If you have ever used MySQL with the [MyISAM](https://dev.mysql.com/doc/refman/8.0/en/myisam-storage-engine.html) engine, and you have done queries like this:

```sql
SELECT COUNT(*) FROM my_table
```

you will have in fact seen that the count returns immediately. The MyISAM engine maintains a count of all rows in a table as part of the low level information for that table, so counts in MySQL/MyISAM, are spectacularly fast.

However, if you have done counts with the other popular MySQL storage engine, [InnoDB](https://dev.mysql.com/doc/refman/8.0/en/innodb-storage-engine.html), or with a PostgreSQL table, your experience will have been quite different. You will have seen that the count takes much longer to be returned.

The fundamental difference between MySQL/MyISAM and both MySQL/InnoDB and PostgreSQL, with regard to counting, is that they both use something called Multiversion Concurrency Control. Without going deeply into that, this essentially means that the database keeps information about old rows in order to better support concurrency and rollback features. Essentially, each unique transaction may see a slightly different version of the data from other transactions in process at the same time.

 Thus, there is no one single count of rows in the database table like there is with a MySQL/MyISAM table. When one does a count, the database engine has to sequentially scan the table to determine how many rows are in the current transaction's view of reality for that table. Here is what that query plan, on a PostgreSQL database, looks like for a database with about 4.6 million rows:

```sql
                                                                 QUERY PLAN                      
------------------------------------------------------------------------------------------------------------------------------------------------------
 Finalize Aggregate  (cost=316766.47..316766.48 rows=1 width=8) (actual time=20100.944..20228.302 rows=1 loops=1)
   ->  Gather  (cost=316766.25..316766.46 rows=2 width=8) (actual time=20089.306..20228.251 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         ->  Partial Aggregate  (cost=315766.25..315766.26 rows=1 width=8) (actual time=19903.963..19903.965 rows=1 loops=3)
               ->  Parallel Seq Scan on telemetries  (cost=0.00..310917.40 rows=1939540 width=0) (actual time=29.600..19732.802 rows=1533488 loops=3)
 Planning Time: 1.838 ms
 JIT:
   Functions: 11
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 16.348 ms, Inlining 0.000 ms, Optimization 1.648 ms, Emission 51.310 ms, Total 69.305 ms
 Execution Time: 25224.462 ms
(12 rows)

```

2.5 seconds.

That's a long time to wait to get a row count.

As a side note, you may have seen a suggestion that it's faster to do a `count(1)` than a `count(*)`, because of the assumption that the `*` requires the database to access the whole row. With PostgreSQL, this is incorrect, and in fact, the `count(1)` version is slightly slower, on average.

The reason for this is that PostgreSQL has optimized `count(*)` as a special case, and it actually treats it as having no arguments at all. The `count(1)` variation has to check, for each row, to validate that `1` is still not null, and that adds a small, but measurable overhead, particularly on very large tables.

# Making Counting with PostgreSQL and MySQL/InnoDB Faster

This performance reality can be problematic if there are legitimate in-app needs to know how many rows are in a table, or to know how many rows a query would return, without actually running the whole query.

Even though the database engines differ, the solutions to this problem for both PostgreSQL and MySQL/InnoDB are similar.

## Sometimes You Can Count It Differently

The basic template for doing a count is this:

```sql
SELECT COUNT(*) FROM my_table;
```

There is another way to think about count queries, though. Consider a table with a primary key of `id`. The above query could equivalently be written as:

```sql
SELECT COUNT(*) FROM (SELECT id FROM my_table) AS count;
```

This is functionally equivalent to the short form of the count, and it will perform the same as the first version, with an identical `EXPLAIN` plan on a PostgreSQL database. There is nothing to be gained there. However, consider a more involved count that is looking for the number of distinct server IDs in a table.

```sql
SELECT COUNT(DISTINCT server_id) FROM telemetries;
```

The `EXPLAIN` plan for this is pretty predictable:

```sql
                                                            QUERY PLAN                                                            
----------------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=349708.21..349708.22 rows=1 width=8) (actual time=13421.207..13421.209 rows=1 loops=1)
   ->  Seq Scan on telemetries  (cost=0.00..338070.97 rows=4654897 width=16) (actual time=23.805..10572.128 rows=4600463 loops=1)
 Planning Time: 0.089 ms
 JIT:
   Functions: 4
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 0.454 ms, Inlining 0.000 ms, Optimization 1.151 ms, Emission 21.551 ms, Total 23.156 ms
 Execution Time: 13421.768 ms
(8 rows)
```

This is very slow on this table, which contains about 4.6 million rows. You can see in the above plan the line, `Seq Scan on telemetries`, which indicates that the database still had to do a sequential scan of the table in order to count those distinct IDs. However, what happens if we rewrite it according to the prior template?

```sql
SELECT
  COUNT(*)
FROM (
  SELECT
    DISTINCT ON (server_id) server_id
  FROM
    telemetries
) AS count;
```

This query will return the same results as the prior example, but consider the plan that the query planner generates for it:

```sql
                                                                                      QUERY PLAN                                 >
--------------------------------------------------------------------------------------------------------------------------------->
 Aggregate  (cost=364483.83..364483.84 rows=1 width=8) (actual time=1315.177..1315.179 rows=1 loops=1)
   ->  Unique  (cost=0.56..364483.68 rows=12 width=16) (actual time=3.273..1315.133 rows=13 loops=1)
         ->  Index Only Scan using telemetries_server_id_data_key_idx on telemetries  (cost=0.56..352846.44 rows=4654897 width=16>
               Heap Fetches: 528435
 Planning Time: 0.121 ms
 JIT:
   Functions: 4
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 0.564 ms, Inlining 0.000 ms, Optimization 0.168 ms, Emission 2.680 ms, Total 3.412 ms
 Execution Time: 1315.854 ms
(10 rows)
```

It is 10x faster than the original version of the count! The magic is seen in the line that reads: `Index Only Scan using`. By rewriting our query, the engine was able to determine that it could leverage an index to find all of the distinct IDs, and then it just has to scan that much smaller set in order to count them.

If you need an exact count, it is worth taking time to ensure that you are doing your query in the most efficient way possible. Think creatively, and use the `EXPLAIN ANALYZE` capability of both PostgreSQL and MySQL to understand what your queries are doing when you are trying to optimize even something so simple as a count. If you can leverage an index to reduce the total number of rows that you are scanning, then you may be able to get an exact count quickly-enough.

Sometimes, this is not possible, however, and so other strategies are needed.

## Tally It Ahead Of Time

If the requirement is to get an exact count of the rows in a table, and to do it quickly, one option is to pay the time-cost for this data in small pieces, ahead of time, by using triggers/functions to maintain a MySQL/MyISAM-like count that is kept up to date at all times.

The approach is to create a table that stores row counts for other tables, and then to use triggers to update the row count on every insert or delete. For PostgreSQL, this is done with a trigger and a PL/pgSQL function.

```sql
--- Only run this a single time, to prepare the table for managing row counts.
CREATE TABLE row_count (
  table_name text PRIMARY KEY,
  tally bigint
);
```

```sql
--- Likewise, only run this once, in order to create the function to do the counting.
CREATE OR REPLACE FUNCTION do_count() RETURNS TRIGGER AS $$
  DECLARE
  BEGIN
    IF TG_OP = 'INSERT' THEN
      EXECUTE 'UPDATE row_count set tally = tally + 1 where table = ''' || TG_TABLE_NAME || '''';
      RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
      EXECUTE 'UPDATE row_count set tally = tally - 1 where table = ''' || TG_TABLE_NAME || '''';
      RETURN OLD;
    END IF;
  END;
$$
LANGUAGE 'plpgsql';
```

```sql
BEGIN;
--- To have accurate counts, the table must be seeded with the current correct numbers.
  INSERT
    INTO row_count (table, tally)
    VALUES (
      'my_table',
      (SELECT count(*) from my_table));

--- And then apply the trigger to my_table.
  CREATE TRIGGER my_table_do_row_count BEFORE INSERT OR DELETE ON my_table
    FOR EACH ROW EXECUTE PROCEDURE do_count();

COMMIT;
```

Replace `my_table` with the name of the table that you want to have instant, up-to-date counts for.

You can then query a current row count from the `row_count` table:

```sql
=> select tally from row_count where table_name = 'servers';
 tally 
-------
    12
(1 row)
```

This can be done with MySQL/InnoDB, as well. The syntax will differ, but the same principle applies.

There is a cost per insert or per delete to maintain this count. Amortized over the life of your data, this extra cost will be insignificant if the data doesn't change much, but could be very burdensome in a table that has a lot of churn.

The other technique that is available for fast counts is to forgo accuracy for speed, and to rely on estimates.

The the PostgreSQL and the MySQL/InnoDB engines maintain estimates of table size. In PostgreSQL, this is in a table called `pg_class`, and in MySQL/InnoDB, this is in a table called `information_schema`. So a quick way to get an estimate of total table size is to query the appropriate table for it:

```sql
=> SELECT reltuples::integer
   FROM pg_class
  WHERE relname = 'telemetries';
```

```sql
=> SELECT table_rows
   FROM information_schema.tables
   WHERE table_name = 'database_name'
   AND table_name = 'table_name';
```

If a ballpark number is sufficient, then this might be all that you need, and it has the benefit of being very fast to query. It will rarely be highly accurate, however.

MySQL has another table, `information_schema.innodb_sys_tablestats`, that also has a `num_rows` field. The manual states, for this field:

```
The current estimated number of rows in the table. Updated after each DML operation. The value could be imprecise if uncommitted transactions are inserting into or deleting from the table.
```

Thus, this is also an estimated number of rows, and in practice, it will tend to return similar results as the previous example.

For PostgreSQL, there is another option. The PostgreSQL query planner keeps an estimate of both the number of rows in a table (the `reltuples` field of `pg_class`), and of the size, in pages, of the table (the `relpages` field of `pg_class`). It is also possible to query the current size of the table on disk, in bytes, separately, as well as to query the size in bytes of each block.

If we assume that the estimated number of rows in `pg_class`, divided by the estimated number of pages (blocks) in `pg_class` provides a relatively accurate number of rows per page of storage, and we then multiply that by the actual number of pages that are in use, as calculated by dividing the actual bytes in use by the block size, the number should be more accurate than the the planner's estimate. It is probably easier to understand this as code than as English sentences:

```sql
SELECT
  (reltuples / relpages) *
  (pg_relation_size('telemetries') / current_setting('block_size')::integer)
  AS count
FROM
  pg_class
WHERE
  relname = 'telemetries';
```

It produces a surprisingly accurate estimate of the table size, in rows. This is actually what the PostgreSQL query planner does to produce accurate estimates of row counts.

# Estimating The Rows In Arbitrary Queries

That last technique is great for very quickly generating a reliable estimate of the row size of an entire table. However, it is useless if the actual need is to estimate the size of the return set of an arbitrary query. Fortunately, there is a similar estimation strategy that can be employed with any query.

If you use the `EXPLAIN` command to analyze a query, you will see that the query planner always reports a row count. That row count is not a precise number. It is an estimate that the query planner builds from the data that it has cached about every table, so it may be incorrect, but it is also generally fairly close to the real numbers.

Because a stored procedure can run any other command or procedure, a stored procedure can run an `EXPLAIN`, and it can extract data from what is returned. Thus, one can build a count estimator that will work for any query by leveraging the query planner to do the heavy lifting, and then just scraping the data from it.

Below is a version of this that I have in use in a working product:

```sql
CREATE FUNCTION count_estimator(query text) RETURNS bigint AS $$
  DECLARE
    rec record;
    rows bigint;
  BEGIN
    FOR rec IN EXECUTE 'EXPLAIN ' || query LOOP
      rows := substring(rec."QUERY PLAN" FROM ' rows=([[:digit:]]+)');
      EXIT WHEN rows IS NOT NULL;
    END LOOP;
    RETURN rows;
  END;
$$ LANGUAGE plpgsql VOLATILE STRICT;
```

This works very well. All that it does is to iterate over the output of an `EXPLAIN`, returning the number following the first *rows=* that it finds in the output. This is very fast. The query planner usually develops a plan in a fraction of a millisecond, even on relatively slow, small hardware installations.

# OK, So What Is The TL;DR? How Do I Make A Count Fast?

In summary, if you want an exact count, there is no magic to make it fast. The best that you can do is to make sure that you are writing the most efficient query possible.

Past that, if you need an accurate per-table count, you can create a stored procedure/trigger combination that will keep track of this, adjusting the count for every insert or delete that occurs. This adds operational overhead to those actions, however, and may make them too slow on a busy database.

The only other option is to accept estimates. There are a variety of approaches, such as querying the same data that the query planner uses to make its estimates, to just using the query planner, and scraping, via a stored procedure, the query planner's estimate of row size.

