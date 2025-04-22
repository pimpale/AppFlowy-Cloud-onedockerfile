#!/bin/bash

# Must be run as postgres user to run SQL commands
psql <<EOF
-- Create user
DO \$\$
BEGIN
   IF NOT EXISTS (
      SELECT
      FROM   pg_catalog.pg_user
      WHERE  usename = '${POSTGRES_USER}') THEN

      CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';
   END IF;
END
\$\$;

-- Create database
DO \$\$
BEGIN
   IF NOT EXISTS (
      SELECT
      FROM   pg_database
      WHERE  datname = '${POSTGRES_DB}') THEN

      CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};
   END IF;
END
\$\$;
EOF