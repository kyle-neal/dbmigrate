-module(dbmigrate_adapter_tests).

-include_lib("eunit/include/eunit.hrl").

cassandra_default_migrations_table_test() ->
    ?assertEqual("schema_migrations",
                 dbmigrate_adapter_cassandra:configured_migrations_table([])).

cassandra_custom_migrations_table_test() ->
    ?assertEqual("custom_schema_migrations",
                 dbmigrate_adapter_cassandra:configured_migrations_table([{migrations_table,
                                                                           "custom_schema_migrations"}])).

cassandra_binary_migrations_table_test() ->
    ?assertEqual("custom_schema_migrations",
                 dbmigrate_adapter_cassandra:configured_migrations_table([{migrations_table,
                                                                           <<"custom_schema_migrations">>}])).

cassandra_connection_migrations_table_state_test() ->
    Conn = make_ref(),
    ok = dbmigrate_adapter_cassandra:store_migrations_table(Conn, "custom_table"),
    ?assertEqual("custom_table", dbmigrate_adapter_cassandra:migrations_table_name(Conn)),
    ok = dbmigrate_adapter_cassandra:erase_migrations_table(Conn),
    ?assertEqual("schema_migrations",
                 dbmigrate_adapter_cassandra:migrations_table_name(Conn)).

cassandra_optional_callbacks_test() ->
    Conn = fake_conn,
    ?assertEqual(ok, dbmigrate_adapter_cassandra:transaction_begin(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_cassandra:transaction_commit(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_cassandra:transaction_start(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_cassandra:transaction_end(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_cassandra:acquire_lock(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_cassandra:release_lock(Conn)).

elasticsearch_default_migration_index_test() ->
    ?assertEqual("schema_migrations",
                 dbmigrate_adapter_elasticsearch:configured_migration_index([])).

elasticsearch_custom_migration_index_test() ->
    ?assertEqual("custom_schema_migrations",
                 dbmigrate_adapter_elasticsearch:configured_migration_index([{migrations_index,
                                                                              "custom_schema_migrations"}])).

elasticsearch_migrations_table_fallback_test() ->
    ?assertEqual("custom_schema_migrations",
                 dbmigrate_adapter_elasticsearch:configured_migration_index([{migrations_table,
                                                                              "custom_schema_migrations"}])).

elasticsearch_binary_migration_index_test() ->
    ?assertEqual("custom_schema_migrations",
                 dbmigrate_adapter_elasticsearch:configured_migration_index([{migrations_index,
                                                                              <<"custom_schema_migrations">>}])).

elasticsearch_optional_callbacks_test() ->
    Conn = fake_conn,
    ?assertEqual(ok, dbmigrate_adapter_elasticsearch:transaction_begin(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_elasticsearch:transaction_commit(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_elasticsearch:transaction_start(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_elasticsearch:transaction_end(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_elasticsearch:acquire_lock(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_elasticsearch:release_lock(Conn)).

pgsql_default_migrations_table_test() ->
    ?assertEqual("schema_migrations",
                 dbmigrate_adapter_pgsql:configured_migrations_table([])).

pgsql_custom_migrations_table_test() ->
    ?assertEqual("custom_schema_migrations",
                 dbmigrate_adapter_pgsql:configured_migrations_table([{migrations_table,
                                                                       "custom_schema_migrations"}])).

pgsql_binary_migrations_table_test() ->
    ?assertEqual("custom_schema_migrations",
                 dbmigrate_adapter_pgsql:configured_migrations_table([{migrations_table,
                                                                       <<"custom_schema_migrations">>}])).

pgsql_connection_migrations_table_state_test() ->
    Conn = make_ref(),
    ok = dbmigrate_adapter_pgsql:store_migrations_table(Conn, "custom_table"),
    ?assertEqual("custom_table", dbmigrate_adapter_pgsql:migrations_table_name(Conn)),
    ok = dbmigrate_adapter_pgsql:erase_migrations_table(Conn),
    ?assertEqual("schema_migrations", dbmigrate_adapter_pgsql:migrations_table_name(Conn)).

pgsql_compatibility_callbacks_test() ->
    Conn = fake_conn,
    ?assertEqual(ok, dbmigrate_adapter_pgsql:transaction_start(Conn)),
    ?assertEqual(ok, dbmigrate_adapter_pgsql:transaction_end(Conn)).
