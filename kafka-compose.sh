#!/bin/bash

version="7.0.1"
img_kafka="confluentinc/cp-kafka:$version"

cwd=$(pwd)
plugins_path="$cwd/quickstart"

function mysql_data() {
  docker cp "$1" quickstart-mysql:/tmp/"$1"
  docker exec -it quickstart-mysql /bin/bash -c "mysql -u confluent -pconfluent connect_test < /tmp/$1"
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
  rm -r "$plugins_path/jars" && rm -r "$plugins_path/file" 
  mkdir -p "$plugins_path/file" && mkdir -p "$plugins_path/jars"
  wget -O "$jdbc_plugin.zip" "https://d1i4a15mxbxib1.cloudfront.net/api/plugins/confluentinc/kafka-connect-jdbc/versions/10.3.3/$jdbc_plugin.zip" && unzip "$jdbc_plugin.zip" -d "$plugins_path/jars"
  wget -O "$1.zip" "http://dev.mysql.com/get/Downloads/Connector-J/$1.zip" && unzip -j "$1" "$1/$1.jar" -d "$plugins_path/jars/$jdbc_plugin/lib"
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
      if [ "$1" = "avro" ]; then
        echo "avro..."
        docker-compose -f docker-compose-avro.yaml up -d
        create_topics_avro
      else
        echo "json..."
        docker-compose up -d
        create_topics
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