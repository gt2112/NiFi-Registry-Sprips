INSERT INTO public.parameters ("name",value,grp) VALUES
	 ('KerberosKeytab','/var/lib/nifi/prd01.keytab','PRD'),
	 ('KerberosPrincipal','prd01@MIT.SUPPORTLAB.COM','PRD'),
	 ('TopicName','JSONTopic01','PRD'),
	 ('DBPassword','nifidata','PRD'),
	 ('DatabaseConnectionURL','jdbc:postgresql://node2.nifiprod-gtorres.coelab.cloudera.com:5432/postgres','PRD'),
	 ('DatabaseUser','nifidata','PRD'),
	 ('BootstrapServers','node2.nifiprod-gtorres.coelab.cloudera.com:9093,node3.nifiprod-gtorres.coelab.cloudera.com:9093,node4.nifiprod-gtorres.coelab.cloudera.com:9093','PRD'),
	 ('GlobalTrustStoreFile','/var/lib/cloudera-scm-agent/agent-cert/cm-auto-global_truststore.jks','PRD'),
	 ('GlobalTrustStorePassword','f1ldPfHc4Zea5izh22r38wzHi6m93PftRCZc0cKJM8A','PRD'),
	 ('FlowFileText','hello PRD','PRD');
	 
	 
	 INSERT INTO public.parameters ("name",value,grp) values ('sourceId','Kafka_PRD','PRD')
