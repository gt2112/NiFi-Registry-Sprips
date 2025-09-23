#!/bin/bash

# ======================================================================================
# Script: import_script.sh
# Author: Gabriel Torres (Cloudera, Inc.)
# Date: 2025-09-15
#
# Description:
#   This script automates the import of a NiFi flow version into a NiFi Registry
#   and can optionally deploy it to a NiFi Process Group. It's designed to be called
#   by a CI/CD pipeline script after a flow file has been copied to the remote host.
#
# Usage:
#   ./import_script.sh <FILENAME> <APPLY_CHANGES> [NEW_FLOW_FLAG] [FLOW_NAME]
#
# Arguments:
#   FILENAME:      The path to the exported NiFi flow JSON file to be imported.
#   APPLY_CHANGES: 'yes' to deploy the flow to a Process Group, 'no' otherwise.
#   NEW_FLOW_FLAG: (Optional) 'new' to create a new flow in the registry and a new Process Group in NiFi.
#   FLOW_NAME:     (Required if NEW_FLOW_FLAG is 'new') The name for the new flow in NiFi Registry
#
# Pre-requisites:
#   - Kerberos ticket for the principal specified in KERBEROS_KEYTAB.
#   - NiFi CLI and NiFi Registry CLI tools must be available in /opt/cloudera/parcels/CFM/TOOLKIT/bin/.
# ======================================================================================

# --- Set Bash options for robustness ---
set -e            # Exit immediately if a command exits with a non-zero status.
set -o pipefail   # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Global Variables ---
FILENAME=$1
APPLY_CHANGES=$2
MAPPING_FILE="/var/lib/nifiregistry/scripts/mapping.tsv"  #File with the map of the remote NiFi Registry flow ID with the local NiFI Registry flow ID and the local NiFI process group
NIFI_CLI_PROPERTIES_FILE="/var/lib/nifiregistry/scripts/cli.properties"
NR_CLI_PROPERTIES_FILE="/var/lib/nifiregistry/scripts/registrycli.properties"
KERBEROS_KEYTAB="/var/lib/nifiregistry/scripts/gtorres.keytab"
KERBEROS_PRINCIPAL="gtorres@MIT.SUPPORTLAB.COM"
LOCAL_NIFI_HOST="node4.nifiprd-gtorres.coelab.cloudera.com"
LOCAL_NIFI_REGISTRY_HOST="node4.nifiprd-gtorres.coelab.cloudera.com"
LOCAL_BUCKET="0897f42b-7098-4bbf-8e33-b03349eef8a1"  #NiFi Registry Bucket ID to store the flows
REGISTRYID="44c56a60-0199-1000-0000-00001ddb43d7"  #niFi Registry ID in tyhe NiFi Registry client to be use

echo "Entering to import flow script..."

# --- Extract flow IDs from filename and mapping file ---

# Extract the remote flow ID from the filename using awk
REMOTE_FLOW_ID=$(echo "${FILENAME}" | awk '{ sub(/.*exported_flow_/,""); sub(/_version.*/,""); print }')
echo "File flow ID: ${REMOTE_FLOW_ID}"


# --- Conditional Logic for Importing or Creating a Flow ---

# Check if the third argument is 'new' to create a new flow in NiFi registry and the new versioned Process group in NiFi
if [[ "$3" == "new" ]]; then
  echo "Creating a new flow..."
  
  # Capture the flow name from the remaining arguments
  local_args=("$@")
  remaining_args=("${local_args[@]:3}")
  FLOW_NAME=$(printf "%s " "${remaining_args[@]}")
  echo "Flow Name: ${FLOW_NAME}"
  # Capture the Process Group Name from the json file
  PG_NAME=$(jq -r '.flowContents.name' ${FILENAME})
  echo "Process Group Name: "${PG_NAME}
  
  # Create an empty Process Group and get its ID
  PROCESS_GROUP_ID=$(/opt/cloudera/parcels/CFM/TOOLKIT/bin/cli.sh nifi pg-create -pgn "${PG_NAME}" -p "${NIFI_CLI_PROPERTIES_FILE}")
  echo "New process group ID: ${PROCESS_GROUP_ID}"
  
  # Authenticate with Kerberos to get a Bearer token
  kinit -kt "${KERBEROS_KEYTAB}" "${KERBEROS_PRINCIPAL}"
  if [ $? -ne 0 ]; then
    echo "Error: Kerberos authentication failed for registry import."
    exit 2
  fi
  
  # Start version control for the new Process Group and get its flowId
  token=$(curl -k -X POST --negotiate -u : "https://${LOCAL_NIFI_HOST}:8443/nifi-api/access/kerberos")
  echo "Starting version control for new Process group ID..."
  
  NEW_FLOW_ID=$(curl -k -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    "https://${LOCAL_NIFI_HOST}:8443/nifi-api/versions/process-groups/${PROCESS_GROUP_ID}" \
    -d '{"versionedFlow": {"registryId": "'"${REGISTRYID}"'","bucketId": "'"${LOCAL_BUCKET}"'","flowName": "'"${FLOW_NAME}"'","action":"COMMIT"},"processGroupRevision": {"clientId": "value","version": 1,"lastModifier": "value"},"disconnectedNodeAcknowledged": true}' | jq -r '.versionControlInformation.flowId')
  
  echo "New flow ID from API: ${NEW_FLOW_ID}"



  # Get a token for the NiFi Registry API call
  token=$(curl -k -X POST --negotiate -u : "https://${LOCAL_NIFI_REGISTRY_HOST}:18433/nifi-registry-api/access/token/kerberos")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to obtain a Bearer token from local registry for import."
    exit 3
  fi

  # Import the flow version using the NiFi Registry API
  curl -k -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d "@${FILENAME}" \
    "https://${LOCAL_NIFI_REGISTRY_HOST}:18433/nifi-registry-api/buckets/${LOCAL_BUCKET}/flows/${NEW_FLOW_ID}/versions/import"
 
  # Update the mapping file with the new remote flow ID and process group ID
  echo "${REMOTE_FLOW_ID}	${NEW_FLOW_ID}	${PROCESS_GROUP_ID}" >> "${MAPPING_FILE}"
    
     

else
  # If not creating a new flow, import the new version into the existing flow
    
  echo "Importing the new flow version into NiFi Registry..."
  # Find the corresponding local flow ID from the mapping file
  LOCAL_FLOW_ID=$(grep "${REMOTE_FLOW_ID}" "${MAPPING_FILE}" | awk '{print $2}')
  echo "Local flow ID: ${LOCAL_FLOW_ID}"
  
  # Authenticate with Kerberos to get a Bearer token
  kinit -kt "${KERBEROS_KEYTAB}" "${KERBEROS_PRINCIPAL}"
  if [ $? -ne 0 ]; then
    echo "Error: Kerberos authentication failed for registry import."
    exit 2
  fi
  
  # Get a token for the API call
  token=$(curl -k -X POST --negotiate -u : "https://${LOCAL_NIFI_REGISTRY_HOST}:18433/nifi-registry-api/access/token/kerberos")
  if [ $? -ne 0 ]; then
    echo "Error: Failed to obtain a Bearer token from local registry for import."
    exit 3
  fi
  
  # Import the flow version using the API
  curl -k -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d "@${FILENAME}" \
    "https://${LOCAL_NIFI_REGISTRY_HOST}:18433/nifi-registry-api/buckets/${LOCAL_BUCKET}/flows/${LOCAL_FLOW_ID}/versions/import"
fi

# --- Conditional Logic for Applying Changes to NiFi ---

# Check if the new flow version should be applied to a NiFi Process Group
if [[ "${APPLY_CHANGES}" == "yes" ]]; then
  #Get Process Group ID from the mapping file
  PROCESS_GROUP_ID=$(grep "${REMOTE_FLOW_ID}" "${MAPPING_FILE}" | awk '{print $3}')

  # Apply the new flow version to the Process Group
  echo "Applying Process group changes for ID: ${PROCESS_GROUP_ID}"
  /opt/cloudera/parcels/CFM/TOOLKIT/bin/cli.sh nifi pg-change-version --processGroupId "${PROCESS_GROUP_ID}" -p "${NIFI_CLI_PROPERTIES_FILE}"

fi
