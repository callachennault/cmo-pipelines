#!/bin/bash

now=$(date "+%Y-%m-%d-%H-%M-%S")
echo date: ${now} : scanning for long running import jobs
myuidoutput=`id`
myuid=-1
if [[ ${myuidoutput} =~ uid=([[:digit:]]+).* ]]; then
    myuid=${BASH_REMATCH[1]}
fi
if [ $myuid -eq -1 ]; then
    echo Error : could not determine uid
    exit 1
fi
ex1="CMD" #exclude the header from ps
ex2="grep\|ps" #exclude grep and ps commands
ex3="importUsers[a-zA-Z0-9-]*.py\|users[a-zA-Z0-9-]*\.sh" #exclude strings from import user scripts
ex4="triage" #exclude triage imports
ex5="stalled" #exclude this command (scan-for-stalled-import-jobs.sh)

importprocesses=`export COLUMNS=24000 ; ps --user $myuid -o pid,start_time,cutime,cmd | grep import | grep -ve "$ex1\|$ex2\|$ex3\|$ex4\|$ex5"`
if [[ $importprocesses =~ .*[[:alnum:]].* ]] ; then
    #running
    hostname=`hostname`
    ### FAILURE EMAIL ###
    EMAIL_BODY="Import processes appear to be stalled.\nHostname: ${hostname}\ndate: ${now}\nrunning processes: see below\n\nPID\tSTART\tCPUTIME\tCMD\n${importprocesses}\n"
    echo -e "Sending email\n$EMAIL_BODY"
    echo -e "$EMAIL_BODY" | mail -s "Alert: Import jobs stalled on ${hostname}" grossb1@mskcc.org heinsz@mskcc.org ochoaa@mskcc.org sheridar@mskcc.org wilson@cbio.mskcc.org
fi
