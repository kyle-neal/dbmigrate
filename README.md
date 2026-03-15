# dbmigrate

dbmigrate is an Erlang migration library that keeps schema changes as versioned Erlang modules and tracks applied versions per app and backend.

It supports these backends:
- cassandra
- elasticsearch
- pgsql

## What dbmigrate does

- Generates timestamped migration modules.
- Discovers available migrations from disk.
- Tracks applied migrations in backend storage.
- Plans what to apply or roll back (all, one, N, to target, specific version, app version).
- Executes migrations inside adapter transaction hooks.

## High-level architecture

- dbmigrate: Public API facade.
- dbmigrate_request: Normalizes API calls into request maps.
- dbmigrate_plan: Pure planning stage, no database side effects.
- dbmigrate_runner: Executes selected migrations and records outcomes.
- dbmigrate_loader: Path resolution, migration discovery, compile-and-load.
- dbmigrate_registry: Adapter-backed applied migration tracking.
- dbmigrate_adapter: Behaviour definition for backend adapters.
- dbmigrate_adapter_pgsql, dbmigrate_adapter_cassandra, dbmigrate_adapter_elasticsearch: Built-in adapters.

## Migration layout

Default migration path:

~~~text
<your_app>/priv/migrations/<backend>/
~~~

Examples:

~~~text
apps/mmerl_core/priv/migrations/pgsql/
apps/mmerl_core/priv/migrations/cassandra/
~~~

Migration filenames are 14-digit timestamp prefixes:

~~~text
20260314120000_add_positions.erl
~~~

Each migration module must export:
- up/1
- down/1

## Add dbmigrate to your app

In your project rebar.config, add dbmigrate as a dependency and ensure you include backend deps as needed.

In your application app.src, add dbmigrate to applications if your release starts it directly.

## Configuration

dbmigrate reads migration config from the target application env under key migrate.

That means settings should live under your app (for example mmerl_core), not under dbmigrate.

### Example in mmerl_core.app.src

~~~erlang
{application, mmerl_core,
 [{description, "MMERL Core"},
	{vsn, "1.0.0"},
	{applications, [kernel, stdlib, dbmigrate]},
	{env,
	 [{migrate,
		 [{pgsql,
			 [{adapter, dbmigrate_adapter_pgsql},
				{host, "127.0.0.1"},
				{port, 5432},
				{username, "postgres"},
				{password, "postgres"},
				{database, "mmerl_core"},
				{timeout, 5000}]},
			{cassandra,
			 [{adapter, dbmigrate_adapter_cassandra},
				{host, "127.0.0.1"},
				{port, 9042},
				{keyspace, "mmerl_core"}]},
			{elasticsearch,
			 [{adapter, dbmigrate_adapter_elasticsearch},
				{host, "127.0.0.1"},
				{port, 9200},
				{index_name, "mmerl_core"},
				{type_name, "_doc"},
				{migrations_index, "mmerl_migrations"}]}]}]}]}.
~~~

### Example in config/sys.config

~~~erlang
[
 {mmerl_core,
	[{migrate,
		[{pgsql,
			[{adapter, dbmigrate_adapter_pgsql},
			 {host, "127.0.0.1"},
			 {port, 5432},
			 {username, "postgres"},
			 {password, "postgres"},
			 {database, "mmerl_core"},
			 {timeout, 5000},
			 {ssl, false}]}
		]}]}
].
~~~

Notes:
- You can override the default migration path with migrate_path in backend config.
- PostgreSQL adapter also supports ssl, verify, cacertfile, depth, and server_name_indication.

## Creating migrations

From an Erlang shell:

~~~erlang
1> dbmigrate:gen_migration(mmerl_core, pgsql, "add positions").
{ok,"apps/mmerl_core/priv/migrations/pgsql/20260314120000_add_positions.erl"}
~~~

Generated migration template example:

~~~erlang
-module('20260314120000_add_positions').
-export([up/1, down/1]).

up(Conn) ->
		%% apply schema/data change
		ok.

down(Conn) ->
		%% rollback schema/data change
		ok.
~~~

## Running migrations

### Simple command form with -s

This form is ideal when arguments are atoms only.

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys \
	-s dbmigrate migrate mmerl_core pgsql \
	-s init stop -noshell
~~~

Makefile-style example:

~~~make
@erl -sname $(PROJECT_NAME)_migrate_db $(EPATH) -config config/sys -s dbmigrate migrate mmerl_core pgsql -s init stop -noshell
~~~

### Advanced command form with -eval

Use -eval for modes that need non-atom values such as counts, versions, or options.

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys -noshell \
	-eval 'dbmigrate:migrate_n(mmerl_core, pgsql, 3), init:stop().'
~~~

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys -noshell \
	-eval 'dbmigrate:migrate_to(mmerl_core, pgsql, "20260314120000_add_positions"), init:stop().'
~~~

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys -noshell \
	-eval 'dbmigrate:migrate(mmerl_core, pgsql, [{app_version, "1.2.3"}]), init:stop().'
~~~

### Rollback examples

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys -noshell \
	-eval 'dbmigrate:rollback_one(mmerl_core, pgsql), init:stop().'
~~~

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys -noshell \
	-eval 'dbmigrate:rollback_n(mmerl_core, pgsql, 2), init:stop().'
~~~

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys -noshell \
	-eval 'dbmigrate:rollback_to(mmerl_core, pgsql, "20260314120000_add_positions"), init:stop().'
~~~

~~~bash
erl -sname mmerl_migrate_db -pa _build/default/lib/*/ebin -config config/sys -noshell \
	-eval 'dbmigrate:rollback_app_version(mmerl_core, pgsql, "1.2.3"), init:stop().'
~~~

## Public API reference

Core operations:
- dbmigrate:gen_migration/3
- dbmigrate:migrate/2
- dbmigrate:migrate/3
- dbmigrate:migrate_one/2
- dbmigrate:migrate_n/3
- dbmigrate:migrate_to/3
- dbmigrate:migrate_specific/3
- dbmigrate:migrate_mark_as_applied/1
- dbmigrate:rollback_one/2
- dbmigrate:rollback_n/3
- dbmigrate:rollback_to/3
- dbmigrate:rollback_app_version/3

## Build and verification

Run the project checks locally:

~~~bash
make check
~~~

This runs eunit, common test, and dialyzer.