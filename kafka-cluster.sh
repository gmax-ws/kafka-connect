#!/bin/bash

version="7.0.1"

img_zookeeper="confluentinc/cp-zookeeper:$version"
img_kafka="confluentinc/cp-kafka:$version"
img_schema_reistry="confluentinc/cp-schema-registry:$version"
img_kafka_connect="confluentinc/cp-kafka-connect:$version"

cwd=$(pwd)
plugins_path="$cwd/quickstart"

function create_cluster() {
  docker rm -f zookeeper
  docker run -d \
    --net=host \
    --name=zookeeper \
    -e ZOOKEEPER_CLIENT_PORT=32181 \
    -e ZOOKEEPER_TICK_TIME=2000 \
    -e ZOOKEEPER_SYNC_LIMIT=2 \
    "$img_zookeeper"
    
  docker rm -f kafka
  docker run -d \
    --net=host \
    --name=kafka \
    -e KAFKA_ZOOKEEPER_CONNECT=localhost:32181 \
    -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:29092 \
    -e KAFKA_BROKER_ID=2 \
    -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
    "$img_kafka"
    
  docker rm -f schema-registry
  docker run -d \
    --net=host \
    --name=schema-registry \
    -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=localhost:29092 \
    -e SCHEMA_REGISTRY_HOST_NAME=localhost \
    -e SCHEMA_REGISTRY_LISTENERS=http://localhost:8081 \
    -e SCHEMA_REGISTRY_DEBUG=true \
    "$img_schema_reistry"
}

function mysql() {
  docker rm -f quickstart-mysql && \
  docker run -d \
    --name=quickstart-mysql \
    --net=host \
    -e MYSQL_ROOT_PASSWORD=confluent \
    -e MYSQL_USER=confluent \
    -e MYSQL_PASSWORD=confluent \
    -e MYSQL_DATABASE=connect_test \
    mysql
}

function mysql_data() {
  docker cp "$1" quickstart-mysql:/tmp/"$1"
  docker exec -it quickstart-mysql /bin/bash -c "mysql -u confluent -pconfluent connect_test < /tmp/$1"
}

# https://docs.confluent.io/5.0.0/installation/docker/docs/installation/connect-avro-jdbc.html

function kafka_connect() {
  docker rm -f kafka-connect
  docker run -d \
    --name=kafka-connect \
    --net=host \
    -e CONNECT_BOOTSTRAP_SERVERS=localhost:29092 \
    -e CONNECT_REST_PORT=8083 \
    -e CONNECT_GROUP_ID="quickstart" \
    -e CONNECT_CONFIG_STORAGE_TOPIC="quickstart-config" \
    -e CONNECT_OFFSET_STORAGE_TOPIC="quickstart-offsets" \
    -e CONNECT_STATUS_STORAGE_TOPIC="quickstart-status" \
    -e CONNECT_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
    -e CONNECT_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
    -e CONNECT_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
    -e CONNECT_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
    -e CONNECT_REST_ADVERTISED_HOST_NAME="localhost" \
    -e CONNECT_PLUGIN_PATH=/usr/share/java,/usr/share/filestream-connectors,/etc/kafka-connect/jars \
    -v "$plugins_path/file":/tmp/quickstart \
    -v "$plugins_path/jars":/etc/kafka-connect/jars \
    "$img_kafka_connect"
}

function kafka_connect_avro() {
  docker rm -f kafka-connect-avro
  docker run -d \
    --name=kafka-connect-avro \
    --net=host \
    -e CONNECT_BOOTSTRAP_SERVERS=localhost:29092 \
    -e CONNECT_REST_PORT=8083 \
    -e CONNECT_GROUP_ID="quickstart-avro" \
    -e CONNECT_CONFIG_STORAGE_TOPIC="quickstart-avro-config" \
    -e CONNECT_OFFSET_STORAGE_TOPIC="quickstart-avro-offsets" \
    -e CONNECT_STATUS_STORAGE_TOPIC="quickstart-avro-status" \
    -e CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1 \
    -e CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=1 \
    -e CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=1 \
    -e CONNECT_KEY_CONVERTER="io.confluent.connect.avro.AvroConverter" \
    -e CONNECT_VALUE_CONVERTER="io.confluent.connect.avro.AvroConverter" \
    -e CONNECT_KEY_CONVERTER_SCHEMA_REGISTRY_URL="http://localhost:8081" \
    -e CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL="http://localhost:8081" \
    -e CONNECT_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
    -e CONNECT_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
    -e CONNECT_REST_ADVERTISED_HOST_NAME="localhost" \
    -e CONNECT_LOG4J_ROOT_LOGLEVEL=DEBUG \
    -e CONNECT_PLUGIN_PATH=/usr/share/java,/usr/share/filestream-connectors,/etc/kafka-connect/jars \
    -v "$plugins_path/file":/tmp/quickstart \
    -v "$plugins_path/jars":/etc/kafka-connect/jars \
    "$img_kafka_connect"
}

function describe() {
  docker run \
    --net=host \
    --rm \
    "$img_kafka" \
    kafka-topics --describe --bootstrap-server localhost:29092
}

function create_topic() {
  docker run \
    --net=host \
    --rm \
    "$img_kafka" \
    kafka-topics --create --topic "$1" --partitions 1 --replication-factor 1 --if-not-exists --bootstrap-server localhost:29092 --config cleanup.policy=compact
}

function create_topics() {
  create_topic "quickstart-offsets"
  create_topic "quickstart-config"
  create_topic "quickstart-status"
}

function create_topics_avro() {
  create_topic "quickstart-avro-offsets"
  create_topic "quickstart-avro-config"
  create_topic "quickstart-avro-status"
}

function prepare() {
  jdbc_plugin="confluentinc-kafka-connect-jdbc-10.3.3"
  mkdir -p "$plugins_path/file" && mkdir -p "$plugins_path/jars" && rm -r "$plugins_path/jars" && rm -r "$plugins_path/file"
  wget -O "$jdbc_plugin.zip" "https://d1i4a15mxbxib1.cloudfront.net/api/plugins/confluentinc/kafka-connect-jdbc/versions/10.3.3/$jdbc_plugin.zip" && unzip "$jdbc_plugin.zip" -d "$plugins_path/jars"
  wget -O "$1.zip" "http://dev.mysql.com/get/Downloads/Connector-J/$1.zip" && unzip -j "$1" "$1/$1.jar" -d "$plugins_path/jars/$jdbc_plugin/lib"
}

function kafka_ui() {
  docker rm -f kafka-ui
  docker run -d \
  --name=kafka-ui \
  --net=host \
  -e SERVER_PORT=8000 \
	-e KAFKA_CLUSTERS_0_NAME=local \
	-e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=localhost:29092 \
  -e KAFKA_CLUSTERS_0_ZOOKEEPER=localhost:32181 \
  -e KAFKA_CLUSTERS_0_SCHEMAREGISTRY=http://localhost:8081 \
  -e KAFKA_CLUSTERS_0_KAFKACONNECT_0_NAME=kafka-connect \
  -e KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS=http://localhost:8083 \
	provectuslabs/kafka-ui:latest 
}

while :; do
  echo "Your working directory is:" && pwd
  PS3="Please enter your choice: "
  options=("Init" "Prepare" "Deploy" "Topics" "MySQL Data" "Quit")
  select opt in "${options[@]}"; do
    case $opt in
    "Init")
      # shellcheck disable=SC2046
      docker rm -f $(docker ps -qa)
      break
      ;;
    "Prepare")
      # shellcheck disable=SC2046
      prepare "mysql-connector-java-5.1.49"
      break
      ;;
    "Deploy")
      create_cluster
      if [ "$1" = "avro" ]; then
        echo "avro..."
        create_topics_avro
        kafka_connect_avro
      else
        echo "json..."
        create_topics
        kafka_connect
      fi
      mysql
      kafka_ui
      break
      ;;
    "Topics")
      describe
      break
      ;;
    "MySQL Data")
      mysql_data "data.sql"
      break
      ;;
    "Quit")
      break 2
      ;;
    *) echo "Invalid option, please select a valid one." ;;
    esac
  done
done