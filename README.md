# dbmigrate

Migration tool for databases

Usage `dbmigrate:gen_migration(mmerl_core, pgsql, "add positions").`

A new migration in the apps `priv/migrations` directory

For this example: `apps/mmerl_core/priv/migrations/pgsql/20260314120000_add_positions.erl`

Databases supported:
- cassandra
- elasticsearch
- pgsql