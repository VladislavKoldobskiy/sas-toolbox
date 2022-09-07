#!/bin/bash

set -e
command -v git >/dev/null 2>&1 || { echo >&2 "This script requires git."; exit 1; }

cd $(dirname $0)
case $1 in
init)
    git init
    git config user.name "Integrity"
    git config user.email $USER@$HOSTNAME
    cat <<EOF > .gitignore
**/Backup
**/Backups
**/Journal
**/logs/
**/Logs/
**/Log/
**/log/
**/Data/valib/
**/data/current_logfiles
**/data/base/
**/data/global/
**/data/pg_*/
**/exploded/
**/MetadataServer/MetadataServerBackupManifest.xml
**/Temp/
**/temp/
**/tmp/
**/webapps/ROOT/
**/work/
**/__pycache__/
AppData/
Documents/
Web/activemq/data
Web/activemq/docs
Web/activemq/examples
Web/activemq/webapps*
Web/Applications/SASWIPSchedulingServices9.4/dip/
Web/gemfire/docs
Web/gemfire/dtd
Web/gemfire/instances
Web/gemfire/SampleCode
Web/gemfire/templates
Web/gemfire/tools
Web/SASEnvironmentManager/
Web/Scripts/
Web/Utilities/
Utilities/
README*
EULA*
NOTICE*
LICENSE*
*.bak
*.pid
*.lck
*.sas7bdat
*.picklist
*.ks
*.ts
*.so
*.jar
*.log
*.ear
*.war
*.png
*.gif
*.par
*.zip
*.tar*
*.rar
*.tkzo
*.stkzo
EOF
    ;;
status|check)
    git status
    ;;
commit)
    git add .
    git commit
    ;;
restore|reset)
    git reset --hard
    ;;
*)
    pwd
    echo "Usage: $(basename $0) <init|status|commit|reset>"
esac
