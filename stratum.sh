#!/bin/bash
SASHOME=/opt/sas/SASHome
SASCONFIG=/opt/sas/SASConfig
THIRDPARTY=/opt/sas/thirdparty
CONTENT_PKS=/opt/sas/content_packs
LEVEL=1
SOLUTION_NAME=core
SASCONFIG_LEV=$SASCONFIG/Lev$LEVEL
SOLR_PATH=$THIRDPARTY/solr-8.5.2
SOLR_PORT=8983
METASERVER=localhost
RGFSERVER=localhost
RGFADMIN_PASSWORD=Orion123
RGFDBUSER_PASSWORD=Orion123
set -e

function await {
    start=$SECONDS
    $@ &
    pid=$!
    spin='-\|/'
    i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(((i + 1) % 4))
        elapsed=$((SECONDS - start))
        printf "\r[$elapsed sec ${spin:$i:1}]"
        sleep .1
    done
    printf "\r"
}

function run_cdt {
    METADATA_PORT=$((8560 + LEVEL))
    if [[ -z "$1" ]]; then
        ACTIONS_XLSX="actions.xlsx"
    else
        ACTIONS_XLSX=$1
    fi
    echo Installing content pack
    await $CONTENT_PKS/rqscdt/cdt_unix.sh -metaserver $METASERVER -metauser rgfadmin -metaport $METADATA_PORT -metapass $RGFADMIN_PASSWORD -lev_path $SASCONFIG_LEV -content_path $CONTENT_PATH -actions_xlsx $ACTIONS_XLSX
}

function unpack_content {
    if [[ ! -f $CONTENT_PKS/$1 ]]; then
        echo "Error: File $CONTENT_PKS/$1 does not exist"
        exit 1
    fi
    echo Unpacking $1...
    await unzip -oq $CONTENT_PKS/$1 -d $CONTENT_PATH
}

function rgf_postgres {
    cd $RGF_ADM_TOOLS/dbscripts/PostgreSQL
    RGFDB_PORT=$((10521 + LEVEL))
    if [[ $1 == "prepare" ]]; then
        await ./PrepareSchema.sh -U rgfdbuser -h $RGFSERVER -p $RGFDB_PORT rgfdbname $2 >/dev/null
    elif [[ $1 == "init" ]]; then
        await ./InitDatabase.sh -U rgfdbuser -h $RGFSERVER -p $RGFDB_PORT rgfdbname $2 >/dev/null
    fi
}

function require_core {
    if [[ ! -d $IRM_FEDERATED/fa.rmc.2021.10 ]]; then
        echo "This solution requires Stratum Core which is not installed."
        echo "Run '$(basename $0) --solution core' to install."
        exit 1
    fi
}

function restart_tomcat {
    if [[ $ROLE == "compute" ]]; then
        echo "Tomcat restart not supported for Compute; please restart WebAppServers manually on a Mid-Tier host."
        read -p "When done, hit Enter to continue."
    else
        echo -e "Restarting SAS Application Server $1"
        $SASCONFIG_LEV/Web/WebAppServer/SASServer$1_1/bin/tcruntime-ctl.sh restart
    fi
}

function run_role {
    if [[ $1 == "midtier" ]]; then
        if [[ -f "/opt/sas/thirdparty/solr-8.5.2/server/solr/rgf/core.properties" ]]; then
            echo "Solr already configured, skipping. Remove solr directory to reconfigure."
        else
            SOLR_SAMPLES=$SASHOME/SASRiskGovernanceFrameworkMidTier/7.4/Config/Samples/Solr852

            echo "Unpacking Solr distro"
            await unzip -oq $THIRDPARTY/solr-8.5.2.zip -d $THIRDPARTY
            cp -v $THIRDPARTY/jhighlight-1.0.jar $SOLR_PATH/server/lib

            echo "Configuring Solr"
            sed -i 's+#SOLR_JAVA_HOME=""+SOLR_JAVA_HOME='$SASHOME'/SASPrivateJavaRuntimeEnvironment/9.4/jre+g' $SOLR_PATH/bin/solr.in.sh
            $SOLR_PATH/bin/solr start -p $SOLR_PORT
            $SOLR_PATH/bin/solr create -c rgf -p $SOLR_PORT
            $SOLR_PATH/bin/solr config -c rgf -p $SOLR_PORT -action set-user-property -property update.autoCreateFields -value false
            await sleep 5

            $SOLR_PATH/bin/solr stop -p $SOLR_PORT
            cp -v $SOLR_SAMPLES/configoverlay.json $SOLR_PATH/server/solr/rgf/conf/
            cp -v $SOLR_SAMPLES/managed-schema $SOLR_PATH/server/solr/rgf/conf/
            cp -v $SOLR_SAMPLES/solrconfig.xml $SOLR_PATH/server/solr/rgf/conf/
            cp -v $SOLR_SAMPLES/log4j2.xml $SOLR_PATH/server/resources/
            echo
            $SOLR_PATH/bin/solr start -m 4g -p $SOLR_PORT
            echo -e "\nSolr configuration completed\n"
        fi
    elif [[ $1 == "compute" ]]; then
        RGF_ADM_TOOLS=$SASCONFIG_LEV/Applications/SASRiskGovernanceFrameworkAdministrativeTools
        IRM_FEDERATED=$SASCONFIG_LEV/AppData/SASIRM
        if [[ $(umask) != "0002" ]]; then
            echo Changing umask to 0002 - was: $(umask)
            umask 0002
        fi

        if [[ $LANG != "en_US.UTF-8" ]]; then
            echo Changing LANG to en_US - was: $LANG
            export LANG=en_US.UTF-8
        fi
        echo "Unpacking RQS Content Deployment Tool"
        await unzip -oq $CONTENT_PKS/rqscdt.v10.2021.zip -d $CONTENT_PKS/rqscdt

        RGFDBUSER_PASSWORD_BASE64=$(echo -n $RGFDBUSER_PASSWORD | base64)
        sed -i 's+# monitor.db.connection.password=+monitor.db.connection.password={SAS001}'$RGFDBUSER_PASSWORD_BASE64'+g' $RGF_ADM_TOOLS/properties/db.AdminTools.properties
        sed -i 's+# wip.db.connection.password=+wip.db.connection.password={SAS001}'$RGFDBUSER_PASSWORD_BASE64'+g' $RGF_ADM_TOOLS/properties/db.AdminTools.properties
        export PATH=$SASHOME/SASWebInfrastructurePlatformDataServer/9.4/bin:$PATH
        export LD_LIBRARY_PATH=$SASHOME/SASWebInfrastructurePlatformDataServer/9.4/lib:$LD_LIBRARY_PATH
        export PGPASSWORD=$RGFDBUSER_PASSWORD
        cd $RGF_ADM_TOOLS/dbscripts
        ./verifyEnvironment.sh

        case $SOLUTION_NAME in
        gcm | GCM)
            CONTENT_PATH=$IRM_FEDERATED/fa.gcm.2020.04
            rgf_postgres prepare gcm
            rgf_postgres init gcm
            unpack_content RGF_GCM_04_2020_update1.zip
            run_cdt
            restart_tomcat 8
            restart_tomcat 12
            ;;
        mrm | MRM)
            CONTENT_PATH=$IRM_FEDERATED/fa.mrm.2020.04
            rgf_postgres prepare mrm
            rgf_postgres init mrm
            unpack_content RGF_MRM_04_2020.zip
            run_cdt
            restart_tomcat 8
            restart_tomcat 12
            ;;
        core | Core)
            CONTENT_PATH=$IRM_FEDERATED/fa.rmc.2021.10
            rgf_postgres prepare rmc
            rgf_postgres init rmc
            rgf_postgres prepare rmcdr
            unpack_content rqsrsc.v10.2021.zip
            run_cdt
            restart_tomcat 8
            restart_tomcat 12
            ;;
        ifrs9 | IFRS9)
            CONTENT_PATH=$IRM_FEDERATED/fa.ifrs9.2020.10
            require_core
            rgf_postgres prepare ifrs9dr
            unpack_content ifrs9.v10.2020.zip
            run_cdt
            restart_tomcat 8
            restart_tomcat 12
            echo "Waiting for RGF to initialize (5 minutes)"
            await sleep 300
            echo "Running install_post_rgf_server_restart script"
            sudo -u rgfadmin env \
                sasUser=rgfadmin sasAdminUser=sasadm@saspw \
                sasPassword=$RGFADMIN_PASSWORD sasAdminPassword=$RGFDBUSER_PASSWORD \
                metaserver=$METASERVER irm_fa_id=ifrs9.2020.10 config_set_id=IFRS9 \
                $SASHOME/SASFoundation/9.4/sas -pagesize max -nonews -stdio \
                <$SASCONFIG_LEV/AppData/SASIRM/fa.ifrs9.2020.10/rgf/sas/config/install_post_rgf_server_restart.sas \
                2>/tmp/install_post_rgf_server_restart.log
            grep ^ERROR: /tmp/install_post_rgf_server_restart.log || echo "No errors found"
            tail -n4 /tmp/install_post_rgf_server_restart.log
            echo "Running upgrade_solutions script"
            sudo -u rgfadmin env \
                sasUser=rgfadmin sasAdminUser=sasadm@saspw \
                sasPassword=$RGFADMIN_PASSWORD sasAdminPassword=$RGFDBUSER_PASSWORD \
                metaserver=$METASERVER backup_root_dir=/tmp/stratum_backup irm_fa_id=ifrs17.2021.10 \
                $SASHOME/SASFoundation/9.4/sas -pagesize max -nonews -stdio \
                <$SASCONFIG_LEV/AppData/SASIRM/fa.rmc.2021.10/rgf/sas/config/upgrade_solutions.sas \
                2>/tmp/upgrade_solutions.log
            grep ^ERROR: /tmp/upgrade_solutions.log || echo "No errors found"
            tail -n4 /tmp/upgrade_solutions.log
            ;;
        ifrs17 | IFRS17)
            CONTENT_PATH=$IRM_FEDERATED/fa.ifrs17.2021.10
            require_core
            rgf_postgres prepare ifrs17dr
            rgf_postgres prepare schema_ifrs17_v102021
            unpack_content ifrs17.v10.2021.zip
            sed -i 's+@irm.fa.path@+'$CONTENT_PATH'/irm/input/staging_uoe+g' $CONTENT_PATH/irm/packages/ifrs17.subprop
            #TODO: VSCode complains about unclosed heredoc in function. Rewrite once I figure this out
            echo "#!/bin/sh -p" >$SASHOME/SASFoundation/9.4/bin/sasenv_local
            echo "export POSTGRES_HOME=$SASHOME/SASWebInfrastructurePlatformDataServer/9.4" >>$SASHOME/SASFoundation/9.4/bin/sasenv_local
            echo "export PATH=$SASHOME/SASWebInfrastructurePlatformDataServer/9.4/bin:\$PATH" >>$SASHOME/SASFoundation/9.4/bin/sasenv_local
            echo "export LD_LIBRARY_PATH=$SASHOME/SASWebInfrastructurePlatformDataServer/9.4/lib:\$LD_LIBRARY_PATH" >>$SASHOME/SASFoundation/9.4/bin/sasenv_local
            $SASCONFIG_LEV/ObjectSpawner/ObjectSpawner.sh restart
            await sleep 10
            run_cdt actions_ifrs17_new.xlsx
            echo "Running upgrade_solutions script"
            sudo -u rgfadmin env \
                sasUser=rgfadmin sasAdminUser=sasadm@saspw \
                sasPassword=$RGFADMIN_PASSWORD sasAdminPassword=$RGFDBUSER_PASSWORD \
                metaserver=$METASERVER backup_root_dir=/tmp/stratum_backup irm_fa_id=ifrs17.2021.10 \
                $SASHOME/SASFoundation/9.4/sas -pagesize max -nonews -stdio \
                <$SASCONFIG_LEV/AppData/SASIRM/fa.rmc.2021.10/rgf/sas/config/upgrade_solutions.sas \
                2>/tmp/upgrade_solutions.log
            grep ^ERROR: /tmp/upgrade_solutions.log || echo "No errors found"
            tail -n4 /tmp/upgrade_solutions.log
            echo Importing database
            await psql -v schema=schema_ifrs17_v102021 -v owner=rgfdbuser -U rgfdbowner -h $RGFSERVER -p 10522 -d rgfdbname -f schema_ifrs17_v102021.sql > /dev/null
            restart_tomcat 8
            restart_tomcat 12
            ;;
        *)
            echo "Unsupported solution: $SOLUTION_NAME"
            echo "$(basename $0) --solution <gcm|mrm|core|ifrs9|ifrs17>"
            exit 1
            ;;
        esac
    fi

}

while [[ $# -gt 0 ]]; do
    case $1 in
    --solution)
        if [[ -z "$2" ]]; then
            echo "--solution parameter supplied without value. Should be: 'gcm', 'mrm', 'core', or 'ifrs17'."
            exit 1
        else
            SOLUTION_NAME="$2"
        fi
        shift #past argument
        shift #past value
        ;;
    --role)
        if [[ -z "$2" ]]; then
            echo "--role parameter supplied without value. Should be one of: 'compute', 'midtier', or 'aio'."
            echo "If role is 'compute', specify the metadata server host name with '--metaserver <host>'"
            exit 1
        else
            ROLE="$2"
        fi
        shift
        shift
        ;;
    --level)
        if (($2 < 1 || $2 > 9)); then
            echo "--level parameter supplied without expected value. Should be 1-9, example: '--level 2'."
            echo "If omitted, default is '$LEVEL'"
            exit 1
        else
            LEVEL=$2
            SASCONFIG_LEV=$SASCONFIG/Lev$LEVEL
        fi
        shift
        shift
        ;;
    --metaserver)
        if [[ -z "$2" ]]; then
            echo "--metaserver parameter supplied without value. Should be a host name or FQDN."
            echo "If omitted, default is '$METASERVER'"
            exit 1
        else
            METASERVER="$2"
        fi
        shift
        shift
        ;;
    --rgfserver)
        if [[ -z "$2" ]]; then
            echo "--rgfserver parameter supplied without value. Should be a host name or FQDN."
            echo "If omitted, default is '$RGFSERVER'"
            exit 1
        else
            METASERVER="$2"
        fi
        shift
        shift
        ;;
    --passwords)
        if [[ -z "$2" ]]; then
            echo "--passwords parameter supplied without value. Should be a cleartext password for both rgfadmin UNIX host account and rgfdbuser PostgreSQL account."
            echo "If omitted, default is '$RGFDBUSER_PASSWORD'"
            exit 1
        else
            RGFDBUSER_PASSWORD="$2"
            RGFADMIN_PASSWORD="$2"
        fi
        shift
        shift
        ;;
    --rgfadmin-pwd)
        if [[ -z "$2" ]]; then
            echo "--rgfadmin-pwd parameter supplied without value. Should be a cleartext password for rgfadmin UNIX host account."
            echo "If omitted, default is '$RGFADMIN_PASSWORD'"
            exit 1
        else
            RGFADMIN_PASSWORD="$2"
        fi
        shift
        shift
        ;;
    --rgfdbuser-pwd)
        if [[ -z "$2" ]]; then
            echo "--rgfdbuser-pwd parameter supplied without value. Should be a cleartext password for rgfdbuser PostgreSQL account."
            echo "If omitted, default is '$RGFDBUSER_PASSWORD'"
            exit 1
        else
            RGFDBUSER_PASSWORD="$2"
        fi
        shift
        shift
        ;;
    *)
        echo "Usage: $(basename $0) --role <aio|compute|midtier> --solution <gcm|mrm|core|ifrs9|ifrs17>"
        echo "[--metaserver <fqdn>] [--rgfserver <fqdn>] [--level <cfg level>]"
        echo "[--rgfadmin-pwd <password> --rgfdbuser-pwd <password> | --passwords <password>]"
        exit 1
        ;;
    esac
done

case $ROLE in
aio)
    run_role midtier
    run_role compute
    ;;
midtier)
    run_role midtier
    ;;
compute)
    run_role compute
    ;;
*)
    echo "Role name is missing or incorrect."
    echo "$(basename $0) --role <aio|compute|midtier>"
    exit 1
    ;;
esac
