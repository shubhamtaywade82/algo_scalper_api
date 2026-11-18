#!/bin/sh
# Runs once, when the Postgres data volume is first created (official image behaviour).
# Rails production uses four databases under one role (primary, cache, queue, cable); the agent has its own role and
# database. Separate roles mean neither app can touch the other's data.
set -eu
: "${ASA_DB_PASSWORD:?ASA_DB_PASSWORD is required}"
: "${OTA_DB_PASSWORD:?OTA_DB_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 -v asa_pw="$ASA_DB_PASSWORD" -v ota_pw="$OTA_DB_PASSWORD" \
  --username "$POSTGRES_USER" --dbname postgres <<'SQL'
CREATE ROLE algo_scalper_api LOGIN PASSWORD :'asa_pw';
CREATE ROLE agent LOGIN PASSWORD :'ota_pw';

CREATE DATABASE algo_scalper_api_production       OWNER algo_scalper_api;
CREATE DATABASE algo_scalper_api_production_cache OWNER algo_scalper_api;
CREATE DATABASE algo_scalper_api_production_queue OWNER algo_scalper_api;
CREATE DATABASE algo_scalper_api_production_cable OWNER algo_scalper_api;
CREATE DATABASE trading                           OWNER agent;
SQL
