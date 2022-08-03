# MySQL Performance Monitoring and Optimization

MySQL is an open source relational database system that, like Linux, started life as a side project. It was initially developed for personal usage from the mSQL project, using a new SQL interface while keeping the same API as mSQL. Like Linux, it has grown from those humble roots since the first release, in 1995, and today a broad range of companies, from the smallest to the biggest, use it to run their mission critical databases.

A key element of MySQL's success has been it's ease-of-use. Getting started with it is usually as a couple commands to install it and then to run it. Developers can have it running in minutes, and can be building tables, inserting data, and running queries immediately after. It feels easy.

In reality, MySQL is a complex system with a delicate balance that you must monitor closely. MySQL itself can help with this, however. It exposes a lot of useful metrics that are useful to identify database engine bottlenecks, to find queries that should be optimized, and even to guage when it's time to upgrade your system.

MySQL organizes data into databases, also called schemas, and tables. Unlike many database systems, however, MySQL allows selection of the low level storage engine to use on a per-schema basis. MySQL 8.0 offers ten different storage engines that one can choose from, each with its own features and operational characteristics. Some of those engines are only used for very narrow purposes, such as the `Blackhole` engine which accepts data but stores nothing, or the `Archive` engine, which uses an extremely compact format for data storage. Most installations, however, depend on one of two engines, `MyISAM` and `InnoDB`.

## Key Metrics Required for Optimizing Your Database

Before you can optimize your database, you need to understand what it is doing, and how it is performing. New Relic provides a [https://docs.newrelic.com/docs/infrastructure/host-integrations/host-integrations-list/mySQL/mysql-integration/](MySQL integration) to allow easy access to a large set of invaluable performance metrics.

### Uptime

This is the simplest metric. Is the MySQL process operational? Don't forget to set up simple downtime alerts, as nothing else matters if the whole database is down.

### Connections

MySQL applies a hard limit to the number of simultaneous connections. If the number of connections reaches this limit, [no more connections will be accepted](https://dev.mysql.com/doc/refman/8.0/en/too-many-connections.html) until the connection count is reduced, or the limit is increased.

MySQL provides a parameter, `max_connections`, which controls this limit. Changing it can be done in your MySQL configuration file, with a line such as:

```
max_connections = 500
```

It can also be done interactively, by sending the following command to MySQL, often via the [MySQL Command Line Client](https://dev.mysql.com/doc/refman/8.0/en/mysql.html):

```
SET GLOBAL max_connections = 500;
```

There are a few things that should be taken into consideration when increasing the limit on the number of max connections.

The first is that there is another parameter, `open_files_limit`, that can affect the number of maximum connections. As of MySQL 8.0, if the value of *`open_files_limit` - 810* is less than the configured `max_connections`, that lesser value will be the effective limit on the maximum number of connections. Also, be aware that optimal configuration for [open_files_limit](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_open_files_limit) can itself take some planning.

Additionally, each of the connections to the database will use some RAM. It's impossible to declare in this article exactly how much RAM those connections will use, but assuming around 3M for each is a good starting point. If you want to determine the maximum that can be used 