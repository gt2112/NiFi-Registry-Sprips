#!/bin/bash
 
FILENAME=$1
APPLY_CHANGES=$2
MAPPING_FILE="/var/lib/nifiregistry/scripts/mapping.tsv"
CLI_PROPERTIES_FILE="/var/lib/nifiregistry/scripts/cli.properties"
KERBEROS_KEYTAB="/var/lib/nifiregistry/scripts/gtorres.keytab"
KERBEROS_PRINCIPAL="gtorres@MIT.SUPPORTLAB.COM"
LOCAL_NIFI_REGISTRY_HOST=node4.nifiprd-gtorres.coelab.cloudera.com
LOCAL_BUCKET="0897f42b-7098-4bbf-8e33-b03349eef8a1"


REMOTE_FLOW_ID=`echo ${FILENAME}| awk '{ sub(/.*exported_flow_/,""); sub(/_version.*/,""); print}'`

echo "file flowID "${REMOTE_FLOW_ID}

LOCAL_FLOW_ID=`grep ${REMOTE_FLOW_ID} ${MAPPING_FILE} | awk '{print $2}'`
echo "local flow id" ${LOCAL_FLOW_ID}

#Import the new flow version in NiFi Registry
echo "Importing a  new flow version in NiFi Registry..."
kinit -kt ${KERBEROS_KEYTAB} ${KERBEROS_PRINCIPAL}
token=`curl -k -X POST --negotiate -u : "https://${LOCAL_NIFI_REGISTRY_HOST}:18433/nifi-registry-api/access/token/kerberos"`
curl -k -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "@${FILENAME}" "https://${LOCAL_NIFI_REGISTRY_HOST}:18433/nifi-registry-api/buckets/${LOCAL_BUCKET}/flows/${LOCAL_FLOW_ID}/versions/import"

# Change process group version if required
if [ "${APPLY_CHANGES}" = "yes" ];then
 PROCESS_GROUP_ID=`grep ${REMOTE_FLOW_ID} ${MAPPING_FILE} | awk '{print $3}'`
 echo "Applying Process group changes... ${PROCESS_GROUP_ID}"
 /opt/cloudera/parcels/CFM/TOOLKIT/bin/cli.sh nifi pg-change-version --processGroupId ${PROCESS_GROUP_ID} -p ${CLI_PROPERTIES_FILE}
fi