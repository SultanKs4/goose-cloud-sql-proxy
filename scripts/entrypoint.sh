#!/bin/bash

if [[ -z "${COMMAND}" ]]; then
    echo "'COMMAND' environment variable not defined. Specify the command for goose app" 1>&2
    exit 1
fi

if [[ -z "${GCP_CREDENTIAL_JSON}" ]]; then
    echo "'GCP_CREDENTIAL_JSON' environment variable not defined. Place the contents of the service account json in this environment variable" 1>&2
    exit 1
else
    # Replace \\n with an actual newline, for .env file compatibility
    echo $GCP_CREDENTIAL_JSON > /tmp/credentials.json
fi

if [[ -z "${CLOUDSQL_INSTANCE}" ]]; then
    echo "'CLOUDSQL_INSTANCE' environment variable not defined. Specify the cloudsql instance in this environment variable" 1>&2
    exit 1
fi

echo "Starting the cloudsql proxy"
echo $CLOUDSQL_INSTANCE
touch /tmp/cloudsql.log
exec /migrator/cloud_sql_proxy -dir=/cloudsql -credential_file /tmp/credentials.json -instances=$CLOUDSQL_INSTANCE > /tmp/cloudsql.log 2>&1 &

# Set true in the shared memory
# Check whether the ready message was received
echo "1" >/dev/shm/cloudsql_ready

# Wait for the cloudsql connection to go up
echo "Waiting for ready message from cloudsql proxy..."

# The tail grep command will get stuck if no ready message arrives, so we set a timer to kill it
# Even if the grep terminates naturally, the tail is running in the background so it needs to be killed
delayTailKill() {
    sleep 10
    # When killing the tail, set the shared memory to zero
    echo "0" >/dev/shm/cloudsql_ready
    pkill -s 0 tail
}
delayTailKill &>/dev/null &

( tail -f -n +1 /tmp/cloudsql.log & ) | grep -q "Ready for new connections" || true

# Remove SA json from the tmp folder
# Nobody should have access either way, but just to check
rm /tmp/credentials.json
# Print the log for debug purposes
tail -n +1 /tmp/cloudsql.log

# Read from shared memory to see if the tail was killed or the ready message arrived
if (( "$(</dev/shm/cloudsql_ready)" != "1" ));
then
  echo "Waiting for cloudsql connection timed out. Exitting."
  # Dump the log so you can see what went wrong
  cat /tmp/cloudsql.log
  exit 1
else
    echo "Cloudsql proxy ready"
fi

# Run goose command with retry and capture result

# Create a full command string by adding the passed in onto goose
GOOSE_COMMAND="goose $COMMAND"

# For Debugging
echo "running $GOOSE_COMMAND"

eval $GOOSE_COMMAND