#!/bin/bash

#### Questions
# 1. What should the name of this script be?

# 2. Should $AZ_MSK_IMPACT_DATA_HOME be under $DMP_DATA_HOME (/data/portal-cron/cbio-portal-data/dmp)
    # or $PORTAL_DATA_HOME (/data/portal-cron/cbio-portal-data)?

# 3. What is location of MSK Solid Heme repo?

# 4. What will structure of az-msk-impact-2022 repo be? Sub-directory with mskimpact data or data at top level?

# 5. Should subset file be written to $MSK_DMP_TMPDIR?

# 6. Should we maintain any history of the changelog files? or let git do this?

# 7. Should name of changelog script change/be made more specific?
    # Right now it's just changelog.py

# 8. When do I add changelog script to cmo-pipelines repo? in my fork?

# 9. python requirements?

# 10. fetch-dmp-data-for-import.sh sends emails for errors - should this script do that?

#### Steps

# 1. Pull latest from AstraZeneca repo (mskcc/az-msk-impact-2022)

printTimeStampedDataProcessingStepMessage "pull of AZ MSKImpact data updates to git repository"
# check updated data back into git
GIT_PULL_FAIL=0
cd $AZ_MSK_IMPACT_DATA_HOME ; $GIT_BINARY pull origin
if [ $? -gt 0 ] ; then
    GIT_PULL_FAIL=1
    sendPreImportFailureMessageMskPipelineLogsSlack "GIT PULL (az-msk-impact-2022) :fire: - address ASAP!"
fi

# -----------------------------------------------------------------------------------
# 2. Copy data from local clone of MSK Solid Heme repo to local clone of AZ repo

# TODO solid_heme repo location
cp -r <solid_heme> $AZ_MSK_IMPACT_DATA_HOME
# TODO error handling

# -----------------------------------------------------------------------------------
# 3. Remove Part C non-consented patients + samples (use python2)
$PYTHON_BINARY $PORTAL_HOME/scripts/generate-clinical-subset.py \
    --study-id="mskimpact" \
    --clinical-file="$AZ_MSK_IMPACT_DATA_HOME/data_clinical_patient.txt" \
    --filter-criteria="PARTC_CONSENTED_12_245=YES" \
    --subset-filename="$MSK_DMP_TMPDIR/az_msk_impact_subset.txt"

# TODO Error handling here

$PYTHON_BINARY $PORTAL_HOME/scripts/merge.py \
    --study-id="mskimpact" \
    --subset="$MSK_DMP_TMPDIR/az_msk_impact_subset.txt" \
    --output-directory="$AZ_MSK_IMPACT_DATA_HOME" \
    --merge-clinical="true" \
    $AZ_MSK_IMPACT_DATA_HOME

# TODO Error handling here

# remove the subset file?

# -----------------------------------------------------------------------------------
# 4. Run changelog script (use python3)
# Should the output file go to a specific directory/filename?
$PYTHON3_BINARY $PORTAL_HOME/scripts/changelog.py $AZ_MSK_IMPACT_DATA_HOME

# TODO Error handling here

# -----------------------------------------------------------------------------------
# 5. Push the updates data to GitHub
printTimeStampedDataProcessingStepMessage "push of AZ MSKImpact data updates to git repository"
# check updated data back into git
GIT_PUSH_FAIL=0
cd $AZ_MSK_IMPACT_DATA_HOME ; $GIT_BINARY push origin
if [ $? -gt 0 ] ; then
    GIT_PUSH_FAIL=1
    sendPreImportFailureMessageMskPipelineLogsSlack "GIT PUSH (az-msk-impact-2022) :fire: - address ASAP!"
fi

