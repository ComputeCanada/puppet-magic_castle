#!/bin/bash
# Tear down the Globus Connect Server endpoint configured by profile::globus.
#
# Run manually, as root, on the Globus node BEFORE destroying the cluster.
# It removes this node from the endpoint, deletes the endpoint (with its
# storage gateways, collections and OIDC server) from Globus, and disables
# the Puppet agent so the endpoint is not registered again.
#
# All values are read from the Globus state files on this node. The endpoint
# cleanup authenticates with the credentials stored in the deployment key.
set -u

STATE_DIR=/var/lib/globus-connect-server
INFO_FILE="${STATE_DIR}/info.json"
DEPLOYMENT_KEY="${STATE_DIR}/gcs-manager/deployment-key.json"
PUPPET=/opt/puppetlabs/bin/puppet
PUPPET_LOCK_TIMEOUT=600

usage() {
  echo "Usage: $(basename "$0") [-y|--yes] [--deployment-key PATH]"
  echo
  echo "Remove this node from its Globus endpoint and delete the endpoint from"
  echo "Globus. Run before destroying the cluster. The Puppet agent is disabled"
  echo "on this node."
  echo
  echo "  -y, --yes                do not ask for confirmation"
  echo "  --deployment-key PATH    endpoint deployment key"
  echo "                           (default: ${DEPLOYMENT_KEY})"
}

ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --deployment-key)
      if [ $# -lt 2 ]; then
        usage >&2
        exit 2
      fi
      DEPLOYMENT_KEY="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$(id -u)" -ne 0 ]; then
  echo "error: $(basename "$0") must be run as root" >&2
  exit 1
fi

if [ ! -s "${INFO_FILE}" ] && [ ! -f "${DEPLOYMENT_KEY}" ]; then
  echo "No Globus node or endpoint configuration found on this host."
  exit 0
fi

# The endpoint ID is also the client ID stored in the deployment key.
ENDPOINT_ID=""
if [ -s "${INFO_FILE}" ]; then
  ENDPOINT_ID=$(jq -r '.endpoint_id // empty' "${INFO_FILE}" 2>/dev/null)
fi
if [ -z "${ENDPOINT_ID}" ] && [ -f "${DEPLOYMENT_KEY}" ]; then
  ENDPOINT_ID=$(jq -r '.client_id // empty' "${DEPLOYMENT_KEY}" 2>/dev/null)
fi

echo "This will permanently delete the Globus endpoint ${ENDPOINT_ID:-(unknown id)}"
echo "including its storage gateways, collections and OIDC server,"
echo "and disable the Puppet agent on this node."
if [ "${ASSUME_YES}" -ne 1 ]; then
  answer=""
  read -r -p "Type 'yes' to continue: " answer
  if [ "${answer}" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
fi

# Puppet would register a new endpoint on its next run once the local state
# below is gone, so disable the agent and wait for any run in progress.
if [ -x "${PUPPET}" ]; then
  echo "==> Disabling the Puppet agent"
  if ! "${PUPPET}" agent --disable "Globus endpoint torn down by $(basename "$0") on $(date -Is)"; then
    echo "error: failed to disable the Puppet agent" >&2
    exit 1
  fi
  lockfile=$("${PUPPET}" config print agent_catalog_run_lockfile 2>/dev/null)
  waited=0
  while [ -n "${lockfile}" ] && [ -e "${lockfile}" ]; do
    if [ "${waited}" -ge "${PUPPET_LOCK_TIMEOUT}" ]; then
      echo "error: a Puppet run is still in progress after ${PUPPET_LOCK_TIMEOUT}s; re-run $(basename "$0") once it ends" >&2
      exit 1
    fi
    echo "    waiting for the Puppet run in progress to finish..."
    sleep 5
    waited=$((waited + 5))
  done
fi

if [ -s "${INFO_FILE}" ]; then
  echo "==> Removing this node from the endpoint"
  if ! globus-connect-server node cleanup; then
    echo "error: node cleanup failed; local state was kept, fix the issue and re-run $(basename "$0")" >&2
    exit 1
  fi
  # Make a re-run skip this step if the endpoint cleanup below fails.
  rm -f "${INFO_FILE}"
fi

if [ -f "${DEPLOYMENT_KEY}" ]; then
  echo "==> Deleting the endpoint from Globus"
  if ! globus-connect-server endpoint cleanup \
      --deployment-key "${DEPLOYMENT_KEY}" \
      --agree-to-delete-endpoint; then
    echo "error: endpoint cleanup failed; the deployment key was kept, fix the issue and re-run $(basename "$0")" >&2
    exit 1
  fi
fi

echo "==> Removing local Globus setup state"
rm -f "${DEPLOYMENT_KEY}" \
  "${STATE_DIR}/gateway.json" \
  "${STATE_DIR}/collection.json" \
  "${STATE_DIR}/oidc.json" \
  "${STATE_DIR}/subscription.json" \
  "${STATE_DIR}"/*-error.json

echo
echo "The Globus endpoint ${ENDPOINT_ID:-(unknown id)} has been deleted."
echo "The Puppet agent is disabled on this node; re-enabling it would register a new endpoint."
echo "It is now safe to destroy the cluster."
