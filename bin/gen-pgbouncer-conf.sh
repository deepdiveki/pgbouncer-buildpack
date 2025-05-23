#!/usr/bin/env bash

POSTGRES_URLS=${PGBOUNCER_URLS:-DATABASE_URL}
POOL_MODE=${PGBOUNCER_POOL_MODE:-transaction}
SERVER_RESET_QUERY=${PGBOUNCER_SERVER_RESET_QUERY}
n=1

if [ -z "${SERVER_RESET_QUERY}" ] && [ "$POOL_MODE" == "session" ]; then
  SERVER_RESET_QUERY="DISCARD ALL;"
fi

mkdir -p /app/vendor/pgbouncer

cat > /app/vendor/pgbouncer/pgbouncer.ini <<EOF
[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6000
auth_type = md5
auth_file = /app/vendor/pgbouncer/users.txt
pool_mode = ${POOL_MODE}
server_reset_query = ${SERVER_RESET_QUERY}
max_client_conn = ${PGBOUNCER_MAX_CLIENT_CONN:-100}
default_pool_size = ${PGBOUNCER_DEFAULT_POOL_SIZE:-1}
min_pool_size = ${PGBOUNCER_MIN_POOL_SIZE:-0}
reserve_pool_size = ${PGBOUNCER_RESERVE_POOL_SIZE:-1}
reserve_pool_timeout = ${PGBOUNCER_RESERVE_POOL_TIMEOUT:-5.0}
server_lifetime = ${PGBOUNCER_SERVER_LIFETIME:-3600}
server_idle_timeout = ${PGBOUNCER_SERVER_IDLE_TIMEOUT:-600}
log_connections = ${PGBOUNCER_LOG_CONNECTIONS:-1}
log_disconnections = ${PGBOUNCER_LOG_DISCONNECTIONS:-1}
log_pooler_errors = ${PGBOUNCER_LOG_POOLER_ERRORS:-1}
stats_period = ${PGBOUNCER_STATS_PERIOD:-60}
ignore_startup_parameters = ${PGBOUNCER_IGNORE_STARTUP_PARAMETERS}
query_wait_timeout = ${PGBOUNCER_QUERY_WAIT_TIMEOUT:-120}

[databases]
EOF

for POSTGRES_URL in $POSTGRES_URLS; do
  eval POSTGRES_URL_VALUE=\$$POSTGRES_URL
  IFS=':' read DB_USER DB_PASS DB_HOST DB_PORT DB_NAME <<< $(echo $POSTGRES_URL_VALUE | perl -lne 'print "$1:$2:$3:$4:$5" if /^postgres(?:ql)?:\/\/([^:]*):([^@]*)@(.*?):(.*?)\/([^?]*?)\?.*$/')

  SCRAM_SECRET=$(printenv "${POSTGRES_URL}_SCRAM_SECRET")
  if [ -z "$SCRAM_SECRET" ]; then
    echo "❌ SCRAM_SECRET missing for $POSTGRES_URL — set ${POSTGRES_URL}_SCRAM_SECRET env var"
    exit 1
  fi

  CLIENT_DB_NAME="db${n}"

  echo "Setting ${POSTGRES_URL}_PGBOUNCER config var"

  if [ "$PGBOUNCER_PREPARED_STATEMENTS" == "false" ]; then
    export "${POSTGRES_URL}_PGBOUNCER=postgres://$DB_USER:$DB_PASS@127.0.0.1:6000/$CLIENT_DB_NAME?prepared_statements=false&sslmode=disable"
  else
    export "${POSTGRES_URL}_PGBOUNCER=postgres://$DB_USER:$DB_PASS@127.0.0.1:6000/$CLIENT_DB_NAME?sslmode=disable"
  fi

  echo "\"$DB_USER\" \"$SCRAM_SECRET\"" >> /app/vendor/pgbouncer/users.txt
  echo "$CLIENT_DB_NAME= host=$DB_HOST dbname=$DB_NAME port=$DB_PORT" >> /app/vendor/pgbouncer/pgbouncer.ini

  let "n += 1"
done

chmod go-rwx /app/vendor/pgbouncer/*
