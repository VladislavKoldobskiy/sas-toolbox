#!/bin/bash
ZONE=public
ACTION=install
RULESET=client
LEVEL=1
FWCMD="firewall-cmd --permanent"
set -e

function create_service {
    if [[ -f /etc/firewalld/services/$1.xml ]]; then
        echo "Service $1 already exists"
    else
        echo -n "Creating service $1... "
        $FWCMD --new-service=$1
    fi
}
function delete_service {
    if [[ -f /etc/firewalld/services/$1.xml ]]; then
        echo -n "Deleting service $1... "
        $FWCMD --delete-service=$1
    else
        echo "Service $1 does not exist"
    fi
}
function set_rule {
    local SERVICE=$1-lev$LEVEL
    local DESCRIPTION=$2
    local PROTO=$3
    shift
    shift
    shift
    local PORTS=("$@")
    $FWCMD -q --service=$SERVICE --set-short="$DESCRIPTION in Lev$LEVEL"
    for i in "${PORTS[@]}"; do
        PORT=$(($i + $LEVEL))
        if [[ $PROTO == "any" ]]; then
            $FWCMD -q --service=$SERVICE --add-port=$PORT/tcp
            $FWCMD -q --service=$SERVICE --add-port=$PORT/udp
        else
            $FWCMD -q --service=$SERVICE --add-port=$PORT/$PROTO || echo "$SERVICE $PORT/$PROTO failed ($?)"
        fi
    done
}
function create_or_delete {
    local ROLE_NAME=$1
    shift
    local SERVICE_NAMES=("$@")
    if [[ $ACTION == "install" ]]; then
        echo -e "\nAdding firewall rules for $ROLE_NAME:"
        for i in "${SERVICE_NAMES[@]}"; do
            create_service $i-lev$LEVEL
            $FWCMD -q --zone=$ZONE --add-service=$i-lev$LEVEL
        done
        echo -n "Configuring rules... "
    else #uninstall
        echo -e "\nRemoving firewall rules for $ROLE_NAME:"
        for i in "${SERVICE_NAMES[@]}"; do
            $FWCMD -q --zone=$ZONE --remove-service=$i-lev$LEVEL
            delete_service $i-lev$LEVEL
        done
    fi
}
function process_rules {
    case $1 in
    metadata)
        SERVICE_NAMES=("sas94-metadata")
        create_or_delete "Metadata Server" $SERVICE_NAMES
        if [[ $ACTION == "install" ]]; then
            set_rule sas94-metadata "SAS 9.4 Metadata Server" any 8560
            echo "ok"
        fi
        ;;
    midtier)
        SERVICE_NAMES=("sas94-http sas94-https sas94-evm-http sas94-evm-https")
        create_or_delete "Middle Tier" $SERVICE_NAMES
        if [[ $ACTION == "install" ]]; then
            set_rule sas94-http "SAS 9.4 Web Server (HTTP)" tcp 7979
            set_rule sas94-https "SAS 9.4 Web Server (HTTPS)" tcp 8342
            set_rule sas94-evm-http "SAS9.4 Environment Manager (HTTP)" tcp 7079
            set_rule sas94-evm-https "SAS9.4 Environment Manager (HTTPS)" tcp 7442
            echo "ok"
        fi
        ;;
    compute)
        SERVICE_NAMES=("sas94-objspawn sas94-wsp sas94-pws sas94-stp sas94-oss sas94-olap sas94-cntspawn")
        create_or_delete "Compute" $SERVICE_NAMES
        if [[ $ACTION == "install" ]]; then
            set_rule sas94-objspawn "SAS 9.4 Object Spawner" tcp 8580 8800 8810 8820
            set_rule sas94-wsp "SAS 9.4 Workspace Server" tcp 8590
            set_rule sas94-pws "SAS 9.4 Pooled Workspace Server" tcp 8700
            set_rule sas94-stp "SAS 9.4 Stored Process Server" tcp 8600 8610 8620 8630
            set_rule sas94-oss "SAS 9.4 Operating System Services" tcp 8450
            set_rule sas94-olap "SAS 9.4 OLAP Server" tcp 5450
            set_rule sas94-cntspawn "SAS 9.4 CONNECT Server" tcp 7540 7550
            echo "ok"
        fi
        ;;
    trust)
        if [[ $ACTION == "install" ]]; then
            echo -n "Adding $2 to trusted zone... "
            $FWCMD --zone=trusted --add-source=$2
        else
            echo -n "Removing $2 from trusted zone... "
            $FWCMD --zone=trusted --remove-source=$2
        fi
        ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case $1 in
    --zone)
        if [[ -z "$2" ]]; then
            echo "--zone parameter supplied without value. Should be: 'public', 'work', 'internal', or other firewall zone name."
            echo "If omitted, default is '$ZONE'."
            exit 1
        else
            ZONE="$2"
        fi
        shift #past argument
        shift #past value
        ;;
    --role)
        if [[ -z "$2" ]]; then
            echo "--role parameter supplied without value. Should be one of: 'metadata', 'compute', 'midtier', or 'aio' for all rules."
            exit 1
        else
            ROLE="$2"
        fi
        shift
        shift
        ;;
    --level)
        if (( $2 < 1 || $2 > 9 )); then
            echo "--level parameter supplied without expected value. Should be 1-9, example: '--level 2'."
            echo "If omitted, default is '$LEVEL'"
            exit 1
        else
            LEVEL=$2
        fi
        shift
        shift
        ;;
    --trust)
        RULESET=trust
        if [[ -z "$2" ]]; then
            echo "--trust parameter supplied without network address. Example: '--trust 10.2.5.0/24'."
            exit 1
        else
            SUBNET="$2"
        fi
        shift
        shift
        ;;
    --uninstall)
        ACTION=uninstall
        shift
        ;;
    *)
        echo "Usage: $(basename $0) --role <aio|metadata|compute|midtier> [--zone <firewall zone>] [--level <cfg level>] [--uninstall]"
        echo "       $(basename $0) --trust <network address> [--uninstall]"
        exit 1
        ;;
    esac
done

if [[ $(id -u) != "0" ]]; then
    echo This script needs to be run as root.
    exit 1
elif [[ $(firewall-cmd --state) != "running" ]]; then
    echo This script requires firewalld to be running.
    exit 1
fi

if [[ $RULESET == "client" ]]; then
    echo "Generating client access rules for Level $LEVEL cfg in firewall zone: $ZONE"
    case $ROLE in
    aio)
        process_rules metadata
        process_rules midtier
        process_rules compute
        ;;
    metadata)
        process_rules metadata
        ;;
    midtier)
        process_rules midtier
        ;;
    compute)
        process_rules compute
        ;;
    *)
        echo "Role name is missing or incorrect."
        echo "$(basename $0) --role <aio|metadata|compute|midtier>"
        exit 1
        ;;
    esac
elif [[ $RULESET == "trust" ]]; then
    echo "Generating server trust rule for $SUBNET"
    process_rules trust $SUBNET
fi
echo -en "\nDone. Reloading firewalld... "
firewall-cmd --reload
