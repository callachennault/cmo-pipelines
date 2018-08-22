#!/bin/bash

MSK_DMP_TMPDIR="$PORTAL_HOME/tmp/import-cron-dmp-msk"
CVR_FETCHER_JAR_FILENAME="$PORTAL_HOME/lib/cvr_fetcher.jar"
IMPORTER_JAR_FILENAME="$PORTAL_HOME/lib/msk-dmp-importer.jar"
JAVA_CVR_FETCHER_ARGS="-jar $CVR_FETCHER_JAR_FILENAME"
JAVA_DEBUG_ARGS="-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=27182"
JAVA_IMPORTER_ARGS="$JAVA_PROXY_ARGS $JAVA_DEBUG_ARGS -Dspring.profiles.active=dbcp -Djava.io.tmpdir=$MSK_DMP_TMPDIR -ea -cp $IMPORTER_JAR_FILENAME org.mskcc.cbio.importer.Admin"
ONCOTREE_VERSION_TO_USE=oncotree_candidate_release

## FUNCTIONS

# Function for alerting slack channel of any failures
function sendFailureMessageMskPipelineLogsSlack {
    MESSAGE=$1
    curl -X POST --data-urlencode "payload={\"channel\": \"#msk-pipeline-logs\", \"username\": \"cbioportal_importer\", \"text\": \"MSK cBio pipelines import process failed: $MESSAGE\", \"icon_emoji\": \":tired_face:\"}" https://hooks.slack.com/services/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
}

# Function for alerting slack channel of successful imports
function sendSuccessMessageMskPipelineLogsSlack {
    STUDY_ID=$1
    curl -X POST --data-urlencode "payload={\"channel\": \"#msk-pipeline-logs\", \"username\": \"cbioportal_importer\", \"text\": \"MSK cBio pipelines import success: $STUDY_ID\", \"icon_emoji\": \":tada:\"}" https://hooks.slack.com/services/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
}

# Function for restarting MSK tomcats
# TODO obviously restartMSKTomcats and restartSchultzTomcats should really be one function ...
function restartMSKTomcats {
    # redeploy war
    echo "Requesting redeployment of msk portal war..."
    echo $(date)
    TOMCAT_HOST_LIST=(dashi.cbio.mskcc.org dashi2.cbio.mskcc.org)
    TOMCAT_HOST_USERNAME=cbioportal_importer
    TOMCAT_HOST_SSH_KEY_FILE=${HOME}/.ssh/id_rsa_msk_tomcat_restarts_key
    TOMCAT_SERVER_RESTART_PATH=/srv/data/portal-cron/msk-tomcat-restart
    TOMCAT_SERVER_PRETTY_DISPLAY_NAME="MSK Tomcat" # e.g. Public Tomcat
    TOMCAT_SERVER_DISPLAY_NAME="msk-tomcat" # e.g. schultz-tomcat
    SSH_OPTIONS="-i ${TOMCAT_HOST_SSH_KEY_FILE} -o BATCHMODE=yes -o ConnectTimeout=3"
    declare -a failed_restart_server_list
    for server in ${TOMCAT_HOST_LIST[@]} ; do
        if ! ssh ${SSH_OPTIONS} ${TOMCAT_HOST_USERNAME}@${server} touch ${TOMCAT_SERVER_RESTART_PATH} ; then
            failed_restart_server_list[${#failed_restart_server_list[*]}]=${server}
        fi
    done
    if [ ${#failed_restart_server_list[*]} -ne 0 ] ; then
        EMAIL_BODY="Attempt to trigger a restart of the $TOMCAT_SERVER_DISPLAY_NAME server on the following hosts failed: ${failed_restart_server_list[*]}"
        echo -e "Sending email $EMAIL_BODY"
        echo -e "$EMAIL_BODY" | mail -s "$TOMCAT_SERVER_PRETTY_DISPLAY_NAME Restart Error : unable to trigger restart" $email_list
    fi
}

# Function for restarting Schultz tomcats
# TODO obviously restartMSKTomcats and restartSchultzTomcats should really be one function ...
function restartSchultzTomcats {
    # redeploy war
    echo "Requesting redeployment of schultz portal war..."
    echo $(date)
    TOMCAT_HOST_LIST=(dashi.cbio.mskcc.org dashi2.cbio.mskcc.org)
    TOMCAT_HOST_USERNAME=cbioportal_importer
    TOMCAT_HOST_SSH_KEY_FILE=${HOME}/.ssh/id_rsa_schultz_tomcat_restarts_key
    TOMCAT_SERVER_RESTART_PATH=/srv/data/portal-cron/schultz-tomcat-restart
    TOMCAT_SERVER_PRETTY_DISPLAY_NAME="Schultz Tomcat" # e.g. Public Tomcat
    TOMCAT_SERVER_DISPLAY_NAME="schultz-tomcat" # e.g. schultz-tomcat
    SSH_OPTIONS="-i ${TOMCAT_HOST_SSH_KEY_FILE} -o BATCHMODE=yes -o ConnectTimeout=3"
    declare -a failed_restart_server_list
    for server in ${TOMCAT_HOST_LIST[@]} ; do
        if ! ssh ${SSH_OPTIONS} ${TOMCAT_HOST_USERNAME}@${server} touch ${TOMCAT_SERVER_RESTART_PATH} ; then
            failed_restart_server_list[${#failed_restart_server_list[*]}]=${server}
        fi
    done
    if [ ${#failed_restart_server_list[*]} -ne 0 ] ; then
        EMAIL_BODY="Attempt to trigger a restart of the $TOMCAT_SERVER_DISPLAY_NAME server on the following hosts failed: ${failed_restart_server_list[*]}"
        echo -e "Sending email $EMAIL_BODY"
        echo -e "$EMAIL_BODY" | mail -s "$TOMCAT_SERVER_PRETTY_DISPLAY_NAME Restart Error : unable to trigger restart" $email_list
    fi
}

# Function for consuming fetched samples after successful import
function consumeSamplesAfterSolidHemeImport {
    if [ -f $MSK_IMPACT_CONSUME_TRIGGER ] ; then
        echo "Consuming mskimpact samples from cvr"
        $JAVA_BINARY $JAVA_CVR_FETCHER_ARGS -c $MSK_IMPACT_DATA_HOME/cvr_data.json
        rm -f $MSK_IMPACT_CONSUME_TRIGGER
    fi
    if [ -f $MSK_HEMEPACT_CONSUME_TRIGGER ] ; then
        echo "Consuming mskimpact_heme samples from cvr"
        $JAVA_BINARY $JAVA_CVR_FETCHER_ARGS -c $MSK_HEMEPACT_DATA_HOME/cvr_data.json
        rm -f $MSK_HEMEPACT_CONSUME_TRIGGER
    fi
}

# -----------------------------------------------------------------------------------------------------------
echo $(date)

email_list="cbioportal-pipelines@cbio.mskcc.org"

if [ -z $JAVA_BINARY ] | [ -z $HG_BINARY ] | [ -z $PORTAL_HOME ] | [ -z $MSK_IMPACT_DATA_HOME ] ; then
    message="test could not run import-dmp-impact.sh: automation-environment.sh script must be run in order to set needed environment variables (like MSK_IMPACT_DATA_HOME, ...)"
    echo ${message}
    echo -e "${message}" |  mail -s "import-dmp-impact-data failed to run." $email_list
    sendFailureMessageMskPipelineLogsSlack "${message}"
    exit 2
fi

# refresh cdd and oncotree cache - by default this script will attempt to
# refresh the CDD and ONCOTREE cache but we should check both exit codes
# independently because of the various dependencies we have for both services
CDD_RECACHE_FAIL=0; ONCOTREE_RECACHE_FAIL=0
bash $PORTAL_HOME/scripts/refresh-cdd-oncotree-cache.sh --cdd-only
if [ $? -gt 0 ]; then
    message="Failed to refresh CDD cache!"
    echo $message
    echo -e "$message" | mail -s "CDD cache failed to refresh" $email_list
    sendFailureMessageMskPipelineLogsSlack "$message"
    CDD_RECACHE_FAIL=1
fi
bash $PORTAL_HOME/scripts/refresh-cdd-oncotree-cache.sh --oncotree-only
if [ $? -gt 0 ]; then
    message="Failed to refresh ONCOTREE cache!"
    echo $message
    echo -e "$message" | mail -s "ONCOTREE cache failed to refresh" $email_list
    sendFailureMessageMskPipelineLogsSlack "$message"
    ONCOTREE_RECACHE_FAIL=1
fi
if [[ $CDD_RECACHE_FAIL -ne 0 || $ONCOTREE_RECACHE_FAIL -ne 0 ]] ; then
    echo "Oncotree and/or CDD recache failed! Exiting..."
    exit 2
fi

now=$(date "+%Y-%m-%d-%H-%M-%S")
mskimpact_notification_file=$(mktemp $MSK_DMP_TMPDIR/mskimpact-portal-update-notification.$now.XXXXXX)
mskheme_notification_file=$(mktemp $MSK_DMP_TMPDIR/mskheme-portal-update-notification.$now.XXXXXX)
mskraindance_notification_file=$(mktemp $MSK_DMP_TMPDIR/mskraindance-portal-update-notification.$now.XXXXXX)
mskarcher_notification_file=$(mktemp $MSK_DMP_TMPDIR/mskarcher-portal-update-notification.$now.XXXXXX)
mixedpact_notification_file=$(mktemp $MSK_DMP_TMPDIR/mixedpact-portal-update-notification.$now.XXXXXX)
msk_solid_heme_notification_file=$(mktemp $MSK_DMP_TMPDIR/msk-solid-heme-portal-update-notification.$now.XXXXXX)
kingscounty_notification_file=$(mktemp $MSK_DMP_TMPDIR/kingscounty-portal-update-notification.$now.XXXXXX)
lehighvalley_notification_file=$(mktemp $MSK_DMP_TMPDIR/lehighvalley-portal-update-notification.$now.XXXXXX)
queenscancercenter_notification_file=$(mktemp $MSK_DMP_TMPDIR/queenscancercenter-portal-update-notification.$now.XXXXXX)
miamicancerinstitute_notification_file=$(mktemp $MSK_DMP_TMPDIR/miamicancerinstitute-portal-update-notification.$now.XXXXXX)
hartfordhealthcare_notification_file=$(mktemp $MSK_DMP_TMPDIR/hartfordhealthcare-portal-update-notification.$now.XXXXXX)
ralphlauren_notification_file=$(mktemp $MSK_DMP_TMPDIR/ralphlauren-portal-update-notification.$now.XXXXXX)
tailormedjapan_notification_file=$(mktemp $MSK_DMP_TMPDIR/msk-tailormedjapan-portal-update-notification.$now.XXXXXX)
lymphoma_super_cohort_notification_file=$(mktemp $MSK_DMP_TMPDIR/lymphoma-super-cohort-portal-update-notification.$now.XXXXXX)
sclc_mskimpact_notification_file=$(mktemp $MSK_DMP_TMPDIR/sclc-mskimpact-portal-update-notification.$now.XXXXXX)
mskimpact_ped_notification_file=$(mktemp $MSK_DMP_TMPDIR/mskimpact-ped-update-notification.$now.XXXXXX)

# -----------------------------------------------------------------------------------------------------------

DB_VERSION_FAIL=0

# Imports assumed to fail until imported successfully
IMPORT_FAIL_IMPACT=1
IMPORT_FAIL_HEME=1
IMPORT_FAIL_RAINDANCE=1
IMPORT_FAIL_ARCHER=1
IMPORT_FAIL_MIXEDPACT=1
IMPORT_FAIL_MSKSOLIDHEME=1
IMPORT_FAIL_KINGS=1
IMPORT_FAIL_LEHIGH=1
IMPORT_FAIL_QUEENS=1
IMPORT_FAIL_MCI=1
IMPORT_FAIL_HARTFORD=1
IMPORT_FAIL_RALPHLAUREN=1
IMPORT_FAIL_TAILORMEDJAPAN=1
IMPORT_FAIL_MSKIMPACT_PED=1
IMPORT_FAIL_SCLC_MSKIMPACT=1
IMPORT_FAIL_LYMPHOMA=1
GENERATE_MASTERLIST_FAIL=0
MERCURIAL_PUSH_FAIL=0

# -------------------------------------------------------------
# check database version before importing anything
echo "Checking if database version is compatible"
echo $(date)
$JAVA_BINARY $JAVA_IMPORTER_ARGS --check-db-version
if [ $? -gt 0 ] ; then
    echo "Database version expected by portal does not match version in database!"
    sendFailureMessageMskPipelineLogsSlack "MSK DMP Importer DB version check"
    DB_VERSION_FAIL=1
fi

if [ $DB_VERSION_FAIL -eq 0 ] ; then
    # import into portal database
    echo "importing cancer type updates into msk portal database..."
    $JAVA_BINARY -Xmx16g $JAVA_IMPORTER_ARGS --import-types-of-cancer --oncotree-version ${ONCOTREE_VERSION_TO_USE}
    if [ $? -gt 0 ] ; then
        sendFailureMessageMskPipelineLogsSlack "Cancer type updates"
    fi
fi

# Temp study importer arguments
# (1): cancer study id [ mskimpact | mskimpact_heme | mskraindance | mskarcher | mixedpact | msk_solid_heme | msk_kingscounty | msk_lehighvalley | msk_queenscancercenter | msk_miamicancerinstitute | msk_hartfordhealthcare | msk_ralphlauren | msk_tailormedjapan | mskimpact_ped | sclc_mskimpact_2017 | lymphoma_super_cohort_fmi_msk ]
# (2): temp study id [ temporary_mskimpact | temporary_mskimpact_heme | temporary_mskraindance | temporary_mskarcher | temporary_mixedpact | temporary_msk_solid_heme | temporary_msk_kingscounty | temporary_msk_lehighvalley | temporary_msk_queenscancercenter | temporary_msk_miamicancerinstitute | temporary_msk_hartfordhealthcare | temporary_msk_ralphlauren | temporary_msk_tailormedjapan | temporary_mskimpact_ped | temporary_sclc_mskimpact_2017 | temporary_lymphoma_super_cohort_fmi_msk]
# (3): backup study id [ yesterday_mskimpact | yesterday_mskimpact_heme | yesterday_mskraindance | yesterday_mskarcher | yesterday_mixedpact | yesterday_msk_solid_heme | yesterday_msk_kingscounty | yesterday_msk_lehighvalley | yesterday_msk_queenscancercenter | yesterday_msk_miamicancerinstitute | yesterday_msk_hartfordhealthcare | yesterday_msk_ralphlauren | yesterday_msk_tailormedjapan | yesterday_mskimpact_ped | yesterday_sclc_mskimpact_2017 | yesterday_lymphoma_super_cohort_fmi_msk]
# (4): portal name [ mskimpact-portal | mskheme-portal | mskraindance-portal | mskarcher-portal | mixedpact-portal | msk-solid-heme-portal |  msk-kingscounty-portal | msk-lehighvalley-portal | msk-queenscancercenter-portal | msk-mci-portal | msk-hartford-portal | msk-ralphlauren-portal | msk-tailormedjapan-portal | msk-ped-portal | msk-sclc-portal | msk-fmi-lymphoma-portal ]
# (5): study path [ $MSK_IMPACT_DATA_HOME | $MSK_HEMEPACT_DATA_HOME | $MSK_RAINDANCE_DATA_HOME | $MSK_ARCHER_DATA_HOME | $MSK_MIXEDPACT_DATA_HOME | $MSK_SOLID_HEME_DATA_HOME | $MSK_KINGS_DATA_HOME | $MSK_LEHIGH_DATA_HOME | $MSK_QUEENS_DATA_HOME | $MSK_MCI_DATA_HOME | $MSK_HARTFORD_DATA_HOME | $MSK_RALPHLAUREN_DATA_HOME | $MSK_TAILORMEDJAPAN_DATA_HOME | $MSKIMPACT_PED_DATA_HOME | $MSK_SCLC_DATA_HOME | $LYMPHOMA_SUPER_COHORT_DATA_HOME ]
# (6): notification file [ $mskimpact_notification_file | $mskheme_notification_file | $mskraindance_notification_file | $mixedpact_notification_file | $msk_solid_heme_notification_file | $kingscounty_notification_file | $lehighvalley_notification_file | $queenscancercenter_notification_file | $miamicancerinstitute_notification_file | $hartfordhealthcare_notification_file | $ralphlauren_notification_file | $tailormedjapan_notification_file | $mskimpact_ped_notification_file | $sclc_mskimpact_notification_file | $lymphoma_super_cohort_notification_file ]
# (7): tmp directory
# (8): email list
# (9): oncotree version [ oncotree_candidate_release | oncotree_latest_stable ]
# (10): importer jar
# (11): transcript overrides source [ uniprot | mskcc ]

RESTART_AFTER_IMPACT_IMPORT=0
# TEMP STUDY IMPORT: MSKSOLIDHEME
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_SOLID_HEME_IMPORT_TRIGGER ] ; then
    echo "Importing MSKSOLIDHEME (will be renamed MSKIMPACT) study..."
    echo $(date)
    # this usage is a little different -- we are comparing the backup-study-id "yesterday_mskimpact" because we will be renaming this imported study to mskimpact after a successful import
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="mskimpact" --temp-study-id="temporary_mskimpact" --backup-study-id="yesterday_mskimpact" --portal-name="msk-solid-heme-portal" --study-path="$MSK_SOLID_HEME_DATA_HOME" --notification-file="$msk_solid_heme_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        consumeSamplesAfterSolidHemeImport
        RESTART_AFTER_IMPACT_IMPORT=1
        IMPORT_FAIL_MSKSOLIDHEME=0
    fi
    rm $MSK_SOLID_HEME_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing MSKSOLIDHEME - database version is not compatible"
    else
        echo "Not importing MSKSOLIDHEME - something went wrong with merging clinical studies"
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for MSKSOLIDHEME
if [ $IMPORT_FAIL_MSKSOLIDHEME -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "MSKSOLIDHEME import"
    echo "MSKSOLIDHEME merge and/or updates failed! Reverting data to last commit."
    cd $MSK_SOLID_HEME_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "MSKSOLIDHEME"
    echo "Committing MSKSOLIDHEME data"
    cd $MSK_SOLID_HEME_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest MSKSOLIDHEME dataset"
fi

## TOMCAT RESTART
# restart tomcat only if the MSK-IMPACT update was succesful
if [ $RESTART_AFTER_IMPACT_IMPORT -eq 0 ] ; then
    echo "Failed to update MSK-IMPACT - next tomcat restart will execute after successful updates to other MSK clinical pipelines and/or MSK affiliate studies..."
    echo $(date)
else
    restartMSKTomcats
fi

# set 'RESTART_AFTER_DMP_PIPELINES_IMPORT' flag to 1 if RAINDANCE, ARCHER, HEMEPACT, MIXEDPACT, or MSKSOLIDHEME succesfully update
RESTART_AFTER_DMP_PIPELINES_IMPORT=0

## TEMP STUDY IMPORT: MSKRAINDANCE
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_RAINDANCE_IMPORT_TRIGGER ] ; then
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="mskraindance" --temp-study-id="temporary_mskraindance" --backup-study-id="yesterday_mskraindance" --portal-name="mskraindance-portal" --study-path="$MSK_RAINDANCE_DATA_HOME" --notification-file="$mskraindance_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_DMP_PIPELINES_IMPORT=1
        IMPORT_FAIL_RAINDANCE=0
    fi
    rm $MSK_RAINDANCE_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing MSKRAINDANCE - database version is not compatible"
    else
        echo "Not importing MSKRAINDANCE - something went wrong with a fetch"
    fi
fi
if [ $IMPORT_FAIL_RAINDANCE -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "RAINDANCE import"
else
    sendSuccessMessageMskPipelineLogsSlack "RAINDANCE"
fi

# TEMP STUDY IMPORT: MSKARCHER
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_ARCHER_IMPORT_TRIGGER ] ; then
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="mskarcher" --temp-study-id="temporary_mskarcher" --backup-study-id="yesterday_mskarcher" --portal-name="mskarcher-portal" --study-path="$MSK_ARCHER_DATA_HOME" --notification-file="$mskarcher_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_DMP_PIPELINES_IMPORT=1
        IMPORT_FAIL_ARCHER=0
    fi
    rm $MSK_ARCHER_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing MSKARCHER - database version is not compatible"
    else
        echo "Not importing MSKARCHER - something went wrong with a fetch"
    fi
fi
if [ $IMPORT_FAIL_ARCHER -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "ARCHER import"
else
    sendSuccessMessageMskPipelineLogsSlack "ARCHER"
fi

## TOMCAT RESTART
# Restart will only execute if at least one of these studies succesfully updated.
#   MSKIMPACT_HEME
#   MSKRAINDANCE
#   MSKARCHER
#   MIXEDPACT
#   MSKSOLIDHEME
if [ $RESTART_AFTER_DMP_PIPELINES_IMPORT -eq 0 ] ; then
    echo "Failed to update HEMEPACT, RAINDANCE, ARCHER, MIXEDPACT, and MSKSOLIDHEME - next tomcat restart will execute after successful updates to MSK affiliate studies..."
    echo $(date)
else
    restartMSKTomcats
fi

## END MSK DMP cohorts imports

#-------------------------------------------------------------------------------------------------------------------------------------
# set 'RESTART_AFTER_MSK_AFFILIATE_IMPORT' flag to 1 if Kings County, Lehigh Valley, Queens Cancer Center, Miami Cancer Institute, MSKIMPACT Ped, or Lymphoma super cohort succesfully update
RESTART_AFTER_MSK_AFFILIATE_IMPORT=0

# TEMP STUDY IMPORT: KINGSCOUNTY
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_KINGS_IMPORT_TRIGGER ] ; then
    echo "Importing msk_kingscounty study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="msk_kingscounty" --temp-study-id="temporary_msk_kingscounty" --backup-study-id="yesterday_msk_kingscounty" --portal-name="msk-kingscounty-portal" --study-path="$MSK_KINGS_DATA_HOME" --notification-file="$kingscounty_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_KINGS=0
    fi
    rm $MSK_KINGS_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing KINGSCOUNTY - database version is not compatible"
    else
        echo "Not importing KINGSCOUNTY - something went wrong with subsetting clinical studies for KINGSCOUNTY."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for KINGSCOUNTY
if [ $IMPORT_FAIL_KINGS -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "KINGSCOUNTY import"
    echo "KINGSCOUNTY subset and/or updates failed! Reverting data to last commit."
    cd $MSK_KINGS_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "KINGSCOUNTY"
    echo "Committing KINGSCOUNTY data"
    cd $MSK_KINGS_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest KINGSCOUNTY dataset"
fi

# TEMP STUDY IMPORT: LEHIGHVALLEY
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_LEHIGH_IMPORT_TRIGGER ] ; then
    echo "Importing msk_lehighvalley study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="msk_lehighvalley" --temp-study-id="temporary_msk_lehighvalley" --backup-study-id="yesterday_msk_lehighvalley" --portal-name="msk-lehighvalley-portal" --study-path="$MSK_LEHIGH_DATA_HOME" --notification-file="$lehighvalley_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_LEHIGH=0
    fi
    rm $MSK_LEHIGH_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing LEHIGHVALLEY - database version is not compatible"
    else
        echo "Not importing LEHIGHVALLEY - something went wrong with subsetting clinical studies for LEHIGHVALLEY."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for LEHIGHVALLEY
if [ $IMPORT_FAIL_LEHIGH -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "LEHIGHVALLEY import"
    echo "LEHIGHVALLEY subset and/or updates failed! Reverting data to last commit."
    cd $MSK_LEHIGH_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "LEHIGHVALLEY"
    echo "Committing LEHIGHVALLEY data"
    cd $MSK_LEHIGH_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest LEHIGHVALLEY dataset"
fi

# TEMP STUDY IMPORT: QUEENSCANCERCENTER
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_QUEENS_IMPORT_TRIGGER ] ; then
    echo "Importing msk_queenscancercenter study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="msk_queenscancercenter" --temp-study-id="temporary_msk_queenscancercenter" --backup-study-id="yesterday_msk_queenscancercenter" --portal-name="msk-queenscancercenter-portal" --study-path="$MSK_QUEENS_DATA_HOME" --notification-file="$queenscancercenter_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_QUEENS=0
    fi
    rm $MSK_QUEENS_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing QUEENSCANCERCENTER - database version is not compatible"
    else
        echo "Not importing QUEENSCANCERCENTER - something went wrong with subsetting clinical studies for QUEENSCANCERCENTER."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for QUEENSCANCERCENTER
if [ $IMPORT_FAIL_QUEENS -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "QUEENSCANCERCENTER import"
    echo "QUEENSCANCERCENTER subset and/or updates failed! Reverting data to last commit."
    cd $MSK_QUEENS_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "QUEENSCANCERCENTER"
    echo "Committing QUEENSCANCERCENTER data"
    cd $MSK_QUEENS_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest QUEENSCANCERCENTER dataset"
fi

# TEMP STUDY IMPORT: MIAMICANCERINSTITUTE
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_MCI_IMPORT_TRIGGER ] ; then
    echo "Importing msk_miamicancerinstitute study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="msk_miamicancerinstitute" --temp-study-id="temporary_msk_miamicancerinstitute" --backup-study-id="yesterday_msk_miamicancerinstitute" --portal-name="msk-mci-portal" --study-path="$MSK_MCI_DATA_HOME" --notification-file="$miamicancerinstitute_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_MCI=0
    fi
    rm $MSK_MCI_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing MIAMICANCERINSTITUTE - database version is not compatible"
    else
        echo "Not importing MIAMICANCERINSTITUTE - something went wrong with subsetting clinical studies for MIAMICANCERINSTITUTE."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for MIAMICANCERINSTITUTE
if [ $IMPORT_FAIL_MCI -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "MIAMICANCERINSTITUTE import"
    echo "MIAMICANCERINSTITUTE subset and/or updates failed! Reverting data to last commit."
    cd $MSK_MCI_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "MIAMICANCERINSTITUTE"
    echo "Committing MIAMICANCERINSTITUTE data"
    cd $MSK_MCI_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest MIAMICANCERINSTITUTE dataset"
fi

# TEMP STUDY IMPORT: HARTFORDHEALTHCARE
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_HARTFORD_IMPORT_TRIGGER ] ; then
    echo "Importing msk_hartfordhealthcare study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="msk_hartfordhealthcare" --temp-study-id="temporary_msk_hartfordhealthcare" --backup-study-id="yesterday_msk_hartfordhealthcare" --portal-name="msk-hartford-portal" --study-path="$MSK_HARTFORD_DATA_HOME" --notification-file="$hartfordhealthcare_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_HARTFORD=0
    fi
    rm $MSK_HARTFORD_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing HARTFORDHEALTHCARE - database version is not compatible"
    else
        echo "Not importing HARTFORDHEALTHCARE - something went wrong with subsetting clinical studies for HARTFORDHEALTHCARE."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for HARTFORDHEALTHCARE
if [ $IMPORT_FAIL_HARTFORD -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "HARTFORDHEALTHCARE import"
    echo "HARTFORDHEALTHCARE subset and/or updates failed! Reverting data to last commit."
    cd $MSK_HARTFORD_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "HARTFORDHEALTHCARE"
    echo "Committing HARTFORDHEALTHCARE data"
    cd $MSK_HARTFORD_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest HARTFORDHEALTHCARE dataset"
fi

# TEMP STUDY IMPORT: RALPHLAUREN
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_RALPHLAUREN_IMPORT_TRIGGER ] ; then
    echo "Importing msk_ralphlauren study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="msk_ralphlauren" --temp-study-id="temporary_msk_ralphlauren" --backup-study-id="yesterday_msk_ralphlauren" --portal-name="msk-ralphlauren-portal" --study-path="$MSK_RALPHLAUREN_DATA_HOME" --notification-file="$ralphlauren_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_RALPHLAUREN=0
    fi
    rm $MSK_RALPHLAUREN_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing RALPHLAUREN - database version is not compatible"
    else
        echo "Not importing RALPHLAUREN - something went wrong with subsetting clinical studies for RALPHLAUREN."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for RALPHLAUREN
if [ $IMPORT_FAIL_RALPHLAUREN -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "RALPHLAUREN import"
    echo "RALPHLAUREN subset and/or updates failed! Reverting data to last commit."
    cd $MSK_RALPHLAUREN_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "RALPHLAUREN"
    echo "Committing RALPHLAUREN data"
    cd $MSK_RALPHLAUREN_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest RALPHLAUREN dataset"
fi

# TEMP STUDY IMPORT: TAILORMEDJAPAN
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_TAILORMEDJAPAN_IMPORT_TRIGGER ] ; then
    echo "Importing msk_tailormedjapan study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="msk_tailormedjapan" --temp-study-id="temporary_msk_tailormedjapan" --backup-study-id="yesterday_msk_tailormedjapan" --portal-name="msk-tailormedjapan-portal" --study-path="$MSK_TAILORMEDJAPAN_DATA_HOME" --notification-file="$tailormedjapan_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_TAILORMEDJAPAN=0
    fi
    rm $MSK_TAILORMEDJAPAN_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing TAILORMEDJAPAN - database version is not compatible"
    else
        echo "Not importing TAILORMEDJAPAN - something went wrong with subsetting clinical studies for TAILORMEDJAPAN."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for TAILORMEDJAPAN
if [ $IMPORT_FAIL_TAILORMEDJAPAN -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "TAILORMEDJAPAN import"
    echo "TAILORMEDJAPAN subset and/or updates failed! Reverting data to last commit."
    cd $MSK_TAILORMEDJAPAN_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "TAILORMEDJAPAN"
    echo "Committing TAILORMEDJAPAN data"
    cd $MSK_TAILORMEDJAPAN_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest TAILORMEDJAPAN dataset"
fi

## END Institute affiliate imports

#-------------------------------------------------------------------------------------------------------------------------------------
# TEMP STUDY IMPORT: MSKIMPACT_PED
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSKIMPACT_PED_IMPORT_TRIGGER ]; then
    echo "Importing mskimpact_ped study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="mskimpact_ped" --temp-study-id="temporary_mskimpact_ped" --backup-study-id="yesterday_mskimpact_ped" --portal-name="msk-ped-portal" --study-path="$MSKIMPACT_PED_DATA_HOME" --notification-file="$mskimpact_ped_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ]; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_MSKIMPACT_PED=0
    fi
    rm $MSKIMPACT_PED_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing MSKIMPACT_PED - database version is not compatible"
    else
        echo "Not importing MSKIMPACT_PED - something went wrong with subsetting clinical studies for MSKIMPACT_PED."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for MSKIMPACT_PED
if [ $IMPORT_FAIL_MSKIMPACT_PED -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "MSKIMPACT_PED import"
    echo "MSKIMPACT_PED subset and/or updates failed! Reverting data to last commit."
    cd $MSKIMPACT_PED_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "MSKIMPACT_PED"
    echo "Committing MSKIMPACT_PED data"
    cd $MSKIMPACT_PED_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest MSKIMPACT_PED dataset"
fi
## END MSKIMPACT_PED import

#-------------------------------------------------------------------------------------------------------------------------------------
RESTART_AFTER_SCLC_IMPORT=0
# TEMP STUDY IMPORT: SCLCMSKIMPACT
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $MSK_SCLC_IMPORT_TRIGGER ] ; then
    echo "Importing sclc_mskimpact_2017 study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="sclc_mskimpact_2017" --temp-study-id="temporary_sclc_mskimpact_2017" --backup-study-id="yesterday_sclc_mskimpact_2017" --portal-name="msk-sclc-portal" --study-path="$MSK_SCLC_DATA_HOME" --notification-file="$sclc_mskimpact_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_SCLC_IMPORT=1
        IMPORT_FAIL_SCLC_MSKIMPACT=0
    fi
    rm $MSK_SCLC_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing SCLCMSKIMPACT - database version is not compatible"
    else
        echo "Not importing SCLCMSKIMPACT - something went wrong with subsetting clinical studies for SCLCMSKIMPACT."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for SCLCMSKIMPACT
if [ $IMPORT_FAIL_SCLC_MSKIMPACT -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "SCLCMSKIMPACT import"
    echo "SCLCMSKIMPACT subset and/or updates failed! Reverting data to last commit."
    cd $MSK_SCLC_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "SCLCMSKIMPACT"
    echo "Committing SCLCMSKIMPACT data"
    cd $MSK_SCLC_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest SCLCMSKIMPACT dataset"
fi
# END SCLCMSKIMPACT import

#-------------------------------------------------------------------------------------------------------------------------------------
# TEMP STUDY IMPORT: LYMPHOMASUPERCOHORT
if [ $DB_VERSION_FAIL -eq 0 ] && [ -f $LYMPHOMA_SUPER_COHORT_IMPORT_TRIGGER ] ; then
    echo "Importing lymphoma 'super' cohort study..."
    echo $(date)
    bash $PORTAL_HOME/scripts/import-temp-study.sh --study-id="lymphoma_super_cohort_fmi_msk" --temp-study-id="temporary_lymphoma_super_cohort_fmi_msk" --backup-study-id="yesterday_lymphoma_super_cohort_fmi_msk" --portal-name="msk-fmi-lymphoma-portal" --study-path="$LYMPHOMA_SUPER_COHORT_DATA_HOME" --notification-file="$lymphoma_super_cohort_notification_file" --tmp-directory="$MSK_DMP_TMPDIR" --email-list="$email_list" --oncotree-version="${ONCOTREE_VERSION_TO_USE}" --importer-jar="$PORTAL_HOME/lib/msk-dmp-importer.jar" --transcript-overrides-source="mskcc"
    if [ $? -eq 0 ] ; then
        RESTART_AFTER_MSK_AFFILIATE_IMPORT=1
        IMPORT_FAIL_LYMPHOMA=0
    fi
    rm $LYMPHOMA_SUPER_COHORT_IMPORT_TRIGGER
else
    if [ $DB_VERSION_FAIL -gt 0 ] ; then
        echo "Not importing LYMPHOMASUPERCOHORT - database version is not compatible"
    else
        echo "Not importing LYMPHOMASUPERCOHORT - something went wrong with subsetting clinical studies for Lymphoma super cohort."
    fi
fi

## TODO: Move commit to fetch-dmp-data-for-import.sh
# commit or revert changes for Lymphoma super cohort
if [ $IMPORT_FAIL_LYMPHOMA -gt 0 ] ; then
    sendFailureMessageMskPipelineLogsSlack "LYMPHOMASUPERCOHORT import"
    echo "Lymphoma super cohort subset and/or updates failed! Reverting data to last commit."
    cd $LYMPHOMA_SUPER_COHORT_DATA_HOME ; $HG_BINARY update -C ; find . -name "*.orig" -delete
else
    sendSuccessMessageMskPipelineLogsSlack "LYMPHOMASUPERCOHORT"
    echo "Committing Lymphoma super cohort data"
    cd $LYMPHOMA_SUPER_COHORT_DATA_HOME ; find . -name "*.orig" -delete ; $HG_BINARY add * ; $HG_BINARY commit -m "Latest Lymphoma Super Cohort dataset"
fi

## TOMCAT RESTART
# Restart will only execute if at least one of these studies succesfully updated.
#   MSK_KINGSCOUNTY
#   MSK_LEHIGHVALLEY
#   MSK_QUEENSCANCERCENTER
#   MSK_MIAMICANCERINSTITUTE
#   MSK_HARTFORDHEALTHCARE
#   MSK_RALPHLAUREN
#   LYMPHOMASUPERCOHORT
#   SCLCMSKIMPACT

if [ $RESTART_AFTER_MSK_AFFILIATE_IMPORT -eq 0 ] ; then
    echo "Failed to update all MSK affiliate studies"
else
    restartMSKTomcats
fi

## SCHULTZ TOMCAT RESTART
# Restart only if sclc_mskimpact_2017 import succeeded
if [ $RESTART_AFTER_SCLC_IMPORT -eq 0 ] ; then
    echo "Failed to update SCLC MSKIMPCAT cohort"
else
    restartSchultzTomcats
fi

## TODO: Move push to fetch-dmp-data-for-import.sh
# check updated data back into mercurial
echo "Pushing DMP-IMPACT updates back to dmp repository..."
echo $(date)
cd $MSK_IMPACT_DATA_HOME ; $HG_BINARY push
if [ $? -gt 0 ] ; then
    MERCURIAL_PUSH_FAIL=1
    sendFailureMessageMskPipelineLogsSlack "HG PUSH :fire: - address ASAP!"
fi

### FAILURE EMAIL ###

EMAIL_BODY="Failed to push outgoing changes to Mercurial - address ASAP!"
# send email if failed to push outgoing changes to mercurial
if [ $MERCURIAL_PUSH_FAIL -gt 0 ] ; then
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" | mail -s "[URGENT] HG PUSH FAILURE" $email_list
fi

EMAIL_BODY="The MSKIMPACT database version is incompatible. Imports will be skipped until database is updated."
# send email if db version isn't compatible
if [ $DB_VERSION_FAIL -gt 0 ] ; then
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" | mail -s "MSKIMPACT Update Failure: DB version is incompatible" $email_list
fi

echo "Fetching and importing of clinical datasets complete!"
echo $(date)


exit 0
