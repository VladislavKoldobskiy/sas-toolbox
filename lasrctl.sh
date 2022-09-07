#!/bin/bash
PORTS=(10011 10031)
SIGPATH="/opt/sas/SASConfig/Lev1/AppData/SASVisualAnalytics/VisualAnalyticsAdministrator/sigfiles"
MIDTIER="http://your.midtier.host:7980"
SAS="/opt/sas/SASHome/SASFoundation/9.4/sas"
TEMPDIR="/tmp"

function generate_sas_script {
    if [ $1 == "start" ]; then
        PROCESSING="Starting"
        SCRIPT="libname lasrctl sasiola startserver=(path=\"$SIGPATH\" keeplog=yes maxlogsize=20) port=$2 tag='hps' signer=\"$MIDTIER/SASLASRAuthorization\"; proc vasmp; serverwait port=$2; quit;"
    elif [ $1 == "stop" ]; then
        PROCESSING="Stopping"
        SCRIPT="proc vasmp; serverterm host=\"localhost\" port=$2; quit;"
    else
        echo "Usage: $0 start|stop"
        exit 1
    fi
}

for i in "${PORTS[@]}"; do
    generate_sas_script $1 $i
    echo "$PROCESSING LASR for port $i"
    echo $SCRIPT >$TEMPDIR/$1LASR$i.sas
    $SAS -sysin $TEMPDIR/$1LASR$i.sas -log $TEMPDIR/$1LASR$i.log &
    sleep 5
    grep ERROR $TEMPDIR/$1LASR$i.log
done
exit 0
