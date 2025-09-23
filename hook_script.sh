#!/bin/bash

# ======================================================================================
# Script: deploy_nifi_flow.sh
# Author: Gabriel Torres
# Date: 2025/09/15
#
# Description:
#   This script automates the process of exporting a new flow version from a local
#   NiFi Registry and conditionally deploying it to a remote NiFi Registry host.
#   It is designed to be triggered NiFi Registry Hook
#
#
# Arguments:
#   EVENT:      The event type that triggered the script (e.g., 'CREATE_FLOW_VERSION').
#   BUCKET_ID:  The ID of the NiFi Registry bucket where the flow is located.
#   FLOW_ID:    The ID of the flow to be exported.
#   VERSION:    The version number of the flow to export.
#   AUTHOR:     The author of the version change.
#   COMMENT:    A string containing the commit comment. This is parsed for
#               deployment flags like "PRODREADY", "AUTO", and "NEW".
#
# Exit Codes:
#   0: Success
#   1: General error
#   2: Authentication failure
#   3: Command failed (e.g., scp, curl)
#
# ======================================================================================


# --- Configuration Variables ---
LOG="/var/lib/nifiregistry/automation/nifi-cli.log"

# Kerberos authentication details
KERBEROS_KEYTAB="/var/lib/nifiregistry/automation/gtorres.keytab"
KERBEROS_PRINCIPAL="gtorres@MIT.SUPPORTLAB.COM"

# NiFi Registry host information
LOCAL_NIFI_REGISTRY_HOSTNAME="node4.nifidev-gtorres.coelab.cloudera.com"
REMOTE_NIFI_REGISTRY_HOSTNAME="node4.nifiprd-gtorres.coelab.cloudera.com"
REMOTE_USERNAME="nifiregistry"
REMOTE_USERNAME_KEY="/var/lib/nifiregistry/automation/id_rsa"

# External script for remote deployment
IMPORT_SCRIPT_PATH="/var/lib/nifiregistry/scripts/import_script.sh"
INCOMING_DIR="/var/lib/nifiregistry/scripts/incoming"



# Assign arguments to meaningful variable names
EVENT=$1
BUCKET=$2
FLOW=$3
VERSION=$4
AUTHOR=$5
# The COMMENT variable captures all arguments from the 6th one onwards
COMMENT="${@:6}"

# Log the received parameters for auditing purposes
echo "--- $(date) ---" >> "$LOG"
echo "Capturing the following Event parameters: " "$@" >> "$LOG"

# --- Main Logic ---

# Check if the event is a new flow version creation
if [[ "$EVENT" == "CREATE_FLOW_VERSION" ]]; then


    # Check if the comment contains the "PRODREADY" flag
    if [[ "$COMMENT" == *"PRODREADY"* ]]; then
		
		
	    # Authenticate with Kerberos and get a bearer token
	    kinit -kt "${KERBEROS_KEYTAB}" "${KERBEROS_PRINCIPAL}"
	    token=$(curl -k -X POST --negotiate -u : "https://${LOCAL_NIFI_REGISTRY_HOSTNAME}:18433/nifi-registry-api/access/token/kerberos")
	    # Check if kinit and curl succeeded
	    if [ $? -ne 0 ] || [ -z "$token" ]; then
	        echo "Error: Failed to obtain Kerberos token or kinit failed." >> "$LOG"
	        exit 2
	    fi

	    # Define the local filename for the exported JSON flow
	    local_filename="exported_flow_${FLOW}_version_${VERSION}.json"
	    echo "Creating filename: ${local_filename}" >> "$LOG"
    
	    # Export the new flow version as a JSON file from the local NiFi Registry API
	    curl -k -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
	         "https://${LOCAL_NIFI_REGISTRY_HOSTNAME}:18433/nifi-registry-api/buckets/$BUCKET/flows/$FLOW/versions/$VERSION/export" > "${local_filename}"
	    # Check if the curl command was successful
	    if [ $? -ne 0 ]; then
	        echo "Error: Failed to export flow from local registry." >> "$LOG"
	        exit 3
	    fi
		
		
        echo "Sending file to remote NiFi Registry Host: ${REMOTE_NIFI_REGISTRY_HOSTNAME}" >> "$LOG"
        # Securely copy the exported JSON file to the remote host
        scp -i "${REMOTE_USERNAME_KEY}" "${local_filename}" "${REMOTE_USERNAME}"@"${REMOTE_NIFI_REGISTRY_HOSTNAME}":"${INCOMING_DIR}"
        # Check if scp succeeded
        if [ $? -ne 0 ]; then
            echo "Error: Failed to copy file to remote host." >> "$LOG"
            exit 3
        fi

        # Use a new variable to define the path to the remote file
        remote_filename="${INCOMING_DIR}/${local_filename}"

        # --- Nested Deployment Logic ---
        # If the comment contains "AUTO", deploy the flow immediately
        if [[ "$COMMENT" == *"AUTO"* ]]; then
            # If the comment also contains "NEW", treat it as a new flow deployment
            if [[ "$COMMENT" == *"NEW"* ]]; then
                echo "Deploying a NEW Flow in the remote NiFi Registry and NiFi..." >> "$LOG"
                # Get the Flow Name from the local registry to use as an argument for the remote script
                FLOW_NAME=$(curl -k -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
                                "https://${LOCAL_NIFI_REGISTRY_HOSTNAME}:18433/nifi-registry-api/flows/$FLOW" | jq -r '.name')
                echo "Flow Name captured: ${FLOW_NAME}" >> "$LOG"

                # Run the import script on the remote host with 'yes new' flags
                ssh -i "${REMOTE_USERNAME_KEY}" "${REMOTE_USERNAME}"@"${REMOTE_NIFI_REGISTRY_HOSTNAME}" \
                    "${IMPORT_SCRIPT_PATH}" "${remote_filename}" yes new "${FLOW_NAME}" >> "$LOG"
            else
                # Deploy a new version of an existing flow
                echo "Deploying a NEW VERSION in the remote NiFi Registry and NiFi..." >> "$LOG"
                # Run the import script on the remote host with the 'yes' flag
                ssh -i "${REMOTE_USERNAME_KEY}" "${REMOTE_USERNAME}"@"${REMOTE_NIFI_REGISTRY_HOSTNAME}" \
                    "${IMPORT_SCRIPT_PATH}" "${remote_filename}" yes >> "$LOG"
            fi
        else
            # If no "AUTO" flag, import the flow without deploying to NiFi
            echo "No 'AUTO' flag found. Importing to remote NiFi Registry only..." >> "$LOG"
            # Run the import script on the remote host with the 'no' flag
            ssh -i "${REMOTE_USERNAME_KEY}" "${REMOTE_USERNAME}"@"${REMOTE_NIFI_REGISTRY_HOSTNAME}" \
                "${IMPORT_SCRIPT_PATH}" "${remote_filename}" no >> "$LOG"
        fi

    else
        # If the comment does not contain the "PRODREADY" flag
        echo "No 'PRODREADY' flag found. The flow will not be deployed to the production registry." >> "$LOG"
    fi
fi
