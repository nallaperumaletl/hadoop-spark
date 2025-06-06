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

# Description: Initializes Hadoop/Spark/Jupyter services

# Log helpers
log_info()  { printf "%b %s\n" "${INFO}" "$1"; }
log_error() { printf "%b %s\n" "${ERROR}" "$1"; }

# Constants
JUPYTER_SERVER_IP="0.0.0.0"
JUPYTER_PORT="8888"
JUPYTER_ROOT_DIR="${HOME}/myfiles"

# Sets JAVA_HOME dynamically based on Java version installed
sed "s|^export JAVA_HOME=.*|export JAVA_HOME=\"${JAVA_HOME}\"|" "${HADOOP_HOME}/etc/hadoop/hadoop-env.sh" > "${HADOOP_HOME}/etc/hadoop/.tmp_hadoop_env"
cp "${HADOOP_HOME}/etc/hadoop/.tmp_hadoop_env" "${HADOOP_HOME}/etc/hadoop/hadoop-env.sh" && rm "${HADOOP_HOME}/etc/hadoop/.tmp_hadoop_env"

start_services() {
    # Format HDFS if necessary
    printf "%b %s" "${INFO}" "Formatting HDFS in namenode..."
    stop-dfs.sh > /dev/null 2>&1
    HDFS_STATUS=$(HADOOP_ROOT_LOGGER=ERROR,console hdfs namenode -format -nonInteractive 2>&1)
    if echo "$HDFS_STATUS" | grep -q "Not formatting."; then
        printf " skipping. Already formatted!\n"
    else
        printf " done!\n"
    fi

    # Start HDFS and YARN services
    # Test if all workers are alive and ready to create the cluster
    ATTEMPTS=0
    while true; do
        REACHABLE_COUNT=0
        while IFS= read -r worker || [[ -n "$worker" ]]; do
            [ -z "$worker" ] && continue
            printf "${INFO} Connecting to ${YELLOW_COLOR}%s${RESET_COLORS}..." "$worker"
            if ssh -o "ConnectTimeout=2" "$worker" "exit" >/dev/null 2>&1 < /dev/null; then
                printf " ${GREEN_COLOR}successful${RESET_COLORS}!\n"
                REACHABLE_COUNT=$((REACHABLE_COUNT + 1))
            else
                printf " ${RED_COLOR}failed${RESET_COLORS}!\n"
            fi
        done < "${HADOOP_CONF_DIR}/workers"
        if [ "${REACHABLE_COUNT}" -ge 1 ]; then
            log_info "Starting cluster with ${YELLOW_COLOR}${REACHABLE_COUNT}${RESET_COLORS} active worker(s)"
            # If all worker nodes are reachable, start services and exit the loop
            # Stopping services (if any leftover processes are still running on the worker nodes)
            stop_services
            sleep 1
            # Starting hdfs
            start-dfs.sh
            # Starting yarn
            start-yarn.sh
            # Starting mapred-history server
            mapred --daemon start historyserver
            # Starting SPARK history server
            start-history-server.sh > /dev/null 2>&1
            # Starting spark connect server (optional)
            if [[ "${SPARK_CONNECT_SERVER}" == "enable" ]] ; then
                start-connect-server.sh --packages org.apache.spark:spark-connect_2.12:${SPARK_VERSION}
            fi
            break
        fi
        # Wait before checking again
        sleep 3

        ATTEMPTS=$((ATTEMPTS+1))
        if [ ${ATTEMPTS} -ge 3 ]; then
            log_error "Failed to reach worker nodes. Retrying in 30 seconds..."
            echo "        Check the configuration files and ensure that all nodes are running."
            sleep 30
            ATTEMPTS=0
        fi
    done

    sleep 2

    BOOT_STATUS=false
    # Creating user folders in HDFS
    if hdfs dfsadmin -report | grep -q "Live datanodes"; then
        log_info "Preparing HDFS directories..."
        HDFS_FOLDERS=(
            "/user/${HDFS_NAMENODE_USER}"
            "/user/${HDFS_NAMENODE_USER}/hadoopLogs"
            "/user/${HDFS_NAMENODE_USER}/sparkLogs" 
            "/user/${HDFS_NAMENODE_USER}/sparkWarehouse"
            "/sparkLibs"
        )
        for FOLDER in "${HDFS_FOLDERS[@]}"; do
            hdfs dfs -mkdir -p "$FOLDER"
        done
        hdfs dfs -put "${SPARK_HOME}/jars/"*.jar /sparkLibs/ 2>/dev/null
        BOOT_STATUS=true
    else
        log_error "HDFS has no live datanodes. Please check the configuration."
        BOOT_STATUS=false
    fi
    
    nohup jupyter lab \
        --ServerApp.ip="${JUPYTER_SERVER_IP}" \
        --ServerApp.port="${JUPYTER_PORT}" \
        --ServerApp.open_browser=False \
        --ServerApp.root_dir="${JUPYTER_ROOT_DIR}" \
        --IdentityProvider.token='' \
        --PasswordIdentityProvider.password_required=False > "${HOME}/.jupyter/jupyter.log" 2>&1 &

    # Checking HDFS status (optional)
    log_info "Checking HDFS nodes report..."
    hdfs dfsadmin -report

    # Checking YARN status (optional)
    log_info "Checking YARN nodes report..."
    yarn node -list

    if [[ "$BOOT_STATUS" == "true" ]]; then
        printf "\nThe following services are now available for access through web browser:\n
        http://localhost:${LIGHTBLUE_COLOR}9870 \t ${YELLOW_COLOR}HDFS${RESET_COLORS}
        http://localhost:${LIGHTBLUE_COLOR}8088 \t ${YELLOW_COLOR}YARN Scheduler${RESET_COLORS}
        http://localhost:${LIGHTBLUE_COLOR}19888 \t ${YELLOW_COLOR}MAPRED Job History${RESET_COLORS}
        http://localhost:${LIGHTBLUE_COLOR}18080 \t ${YELLOW_COLOR}SPARK History Server${RESET_COLORS}\n
        http://localhost:${LIGHTBLUE_COLOR}8888 \t ${YELLOW_COLOR}Jupyter Lab${RESET_COLORS}\n\n"
        log_info "${GREEN_COLOR}$(tput blink)ALL SET!${RESET_COLORS}"
        printf "\nTIP: To access spark-master, type: ${YELLOW_COLOR}docker exec -it spark-master bash${RESET_COLORS}\n\n"
    else
        log_error "Some errors occurred. Please review them and try again."
    fi
}

stop_services() {
    # Stops HDFS, YARN and JUPYTERLAB services
    pgrep -f "jupyter-lab.*--ServerApp.root_dir=${JUPYTER_ROOT_DIR}" | xargs -r kill
    mapred --daemon stop historyserver
    stop-yarn.sh > /dev/null 2>&1
    stop-dfs.sh > /dev/null 2>&1
    stop-history-server.sh > /dev/null 2>&1
}

case "$1" in
  start)
    start_services # also calls stop_services() (i.e. restart)
    ;;
  stop)
    printf "%b %s" "${INFO}" "Stopping services..."
    stop_services
    printf " done!\n"
    ;;
  *)
    printf "Usage: $(basename "$0") {start|stop}\n"
    exit 1
    ;;
esac

exit 0
