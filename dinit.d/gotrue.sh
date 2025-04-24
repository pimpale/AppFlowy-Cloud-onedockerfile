#!/usr/bin/env sh

set -e

export PORT=9999

/usr/local/bin/auth migrate
if [ -n "${GOTRUE_ADMIN_EMAIL}" ] && [ -n "${GOTRUE_ADMIN_PASSWORD}" ]; then
    set +e
    echo "Creating admin user for gotrue..."
    command_output=$(/usr/local/bin/auth admin createuser --admin --confirm "${GOTRUE_ADMIN_EMAIL}" "${GOTRUE_ADMIN_PASSWORD}" 2>&1)
    command_status=$?
    # Check if the command failed
    if [ $command_status -ne 0 ]; then
      # Check if the output contains the specific keyword
      if echo "$command_output" | grep -q "user already exists"; then
        echo "Admin user already exists. Skipping..."
      else
        echo "Command failed. Exiting."
        echo $command_output
        exit $command_status
      fi
    fi
fi
set -e
/usr/local/bin/auth
