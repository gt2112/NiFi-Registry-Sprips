#!/bin/bash

LOG="/var/lib/nifiregistry/automation/nifi-cli.log"

echo "Caturing the following Event parameters: "  $@ >> $LOG

EVENT=$1
BUCKET=$2
FLOW=$3
VERSION=$4
AUTHOR=$5
COMMENT="${@:6}"


KERBEROS_KEYTAB="/var/lib/nifiregistry/automation/gtorres.keytab"
KERBEROS_PRINCIPAL="gtorres@MIT.SUPPORTLAB.COM"

LOCAL_NIFI_REGISTRY_HOSTNAME="node4.nifidev-gtorres.coelab.cloudera.com"
REMOTE_NIFI_REGISTRY_HOSTNAME="node4.nifiprd-gtorres.coelab.cloudera.com"
REMOTE_USERNAME="nifiregistry"
REMOTE_USERNAME_KEY="/var/lib/nifiregistry/automation/id_rsa"

#echo "Event "$EVENT >> $LOG
#echo "Bucket "$BUCKET >> $LOG
#echo "Flow "$FLOW >> $LOG
#echo "Version "$VERSION >> $LOG
#echo "Comment "$COMMENT >> $LOG


# We want to do something only when a new version of a flow is being versioned
if [[ "$EVENT" == "CREATE_FLOW_VERSION" ]]; then
	
   #Export new version as a json file
   kinit -kt ${KERBEROS_KEYTAB} ${KERBEROS_PRINCIPAL}
   token=`curl -k -X POST --negotiate -u : "https://${LOCAL_NIFI_REGISTRY_HOSTNAME}:18433/nifi-registry-api/access/token/kerberos"`
   echo Creating filename: exported_flow_${FLOW}_version_${VERSION}.json >> $LOG
   curl -k -H "Authorization: Bearer $token" -H "Content-Type: application/json" https://${LOCAL_NIFI_REGISTRY_HOSTNAME}:18433/nifi-registry-api/buckets/$BUCKET/flows/$FLOW/versions/$VERSION/export >> exported_flow_${FLOW}_version_${VERSION}.json

  #Copy Json file to the Production NiFi Registry host if the comment contains PRODREADY string:
  if [[ "$COMMENT" == *"PRODREADY"* ]]; then
     echo "Sending to remote NiFi Registry Host" ${REMOTE_NIFI_REGISTRY_HOSTNAME}>> $LOG
     scp -i ${REMOTE_USERNAME_KEY} exported_flow_${FLOW}_version_${VERSION}.json ${REMOTE_USERNAME}@${REMOTE_NIFI_REGISTRY_HOSTNAME}:/var/lib/nifiregistry/scripts/incoming

   # Deployig the new version in the remote NiFi Registry and NiFi if required
   if [[ "$COMMENT" == *"AUTO"* ]]; then
      echo "Deploying in remote NiFi Registry and NiFi..." >> $LOG
      ssh -i ${REMOTE_USERNAME_KEY} ${REMOTE_USERNAME}@${REMOTE_NIFI_REGISTRY_HOSTNAME} /var/lib/nifiregistry/scripts/import_script.sh /var/lib/nifiregistry/scripts/incoming/exported_flow_${FLOW}_version_${VERSION}.json yes >> $LOG
    else
        echo "No auto deploying in remote NiFI ..." >> $LOG
        ssh -i ${REMOTE_USERNAME_KEY} ${REMOTE_USERNAME}@${REMOTE_NIFI_REGISTRY_HOSTNAME} /var/lib/nifiregistry/scripts/import_script.sh /var/lib/nifiregistry/scripts/incoming/exported_flow_${FLOW}_version_${VERSION}.json no >> $LOG
   fi

  fi

fi