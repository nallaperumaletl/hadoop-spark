#!/usr/bin/env bash
# ██████╗  ██████╗ █████╗
# ██╔══██╗██╔════╝██╔══██╗
# ██║  ██║██║     ███████║
# ██║  ██║██║     ██╔══██║
# ██████╔╝╚██████╗██║  ██║
# ╚═════╝  ╚═════╝╚═╝  ╚═╝
# DEPARTAMENTO DE ENGENHARIA DE COMPUTACAO E AUTOMACAO
# UNIVERSIDADE FEDERAL DO RIO GRANDE DO NORTE, NATAL/RN
#
# (C) 2022-2025 CARLOS M D VIEGAS
# https://github.com/cmdviegas
#
# Description: This is a bash script to download Hadoop and Spark (if needed) through GNU/Linux or WSL Terminal

if [ -f "${PWD}/.env" ]; then
  HADOOP_VERSION=$(grep '^HADOOP_VERSION=' "${PWD}/.env" | cut -d '=' -f2)
  SPARK_VERSION=$(grep '^SPARK_VERSION=' "${PWD}/.env" | cut -d '=' -f2)
else
  echo "Error: .env file not found."
  exit 1
fi

if [ -z "$HADOOP_VERSION" ] || [ -z "$SPARK_VERSION" ]; then
  echo "Error: HADOOP_VERSION and SPARK_VERSION must be defined in .env file."
  exit 1
fi

echo "Downloading Apache Hadoop $HADOOP_VERSION and Apache Spark $SPARK_VERSION ..."
wget -nc --inet4-only --no-check-certificate "https://dlcdn.apache.org/hadoop/core/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz"
wget -nc --inet4-only --no-check-certificate "https://dlcdn.apache.org/spark/spark-$SPARK_VERSION/spark-$SPARK_VERSION-bin-hadoop3.tgz"
