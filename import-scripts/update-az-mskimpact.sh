#!/bin/bash

#### Questions
# What should the name of this script be?

# What will structure of az-msk-impact-2022 repo be? Sub-directory with mskimpact data or data at top level?
    # Ask Ben

# Should we maintain any history of the changelog files? or let git do this?
    # maybe ask AZ - accumulate files with timestamps or overwrite?

# ------------------------------------------------------------------------

# When do I add changelog script to cmo-pipelines repo? in my fork?
    # unit tests will go with it

# python requirements?

export AZ_DATA_HOME=$PORTAL_DATA_HOME/az-msk-impact-2022
export AZ_MSK_IMPACT_DATA_HOME=$AZ_DATA_HOME/mskimpact
export AZ_TMPDIR=$AZ_DATA_HOME/tmp

# 1. Pull latest from AstraZeneca repo (mskcc/az-msk-impact-2022)
printTimeStampedDataProcessingStepMessage "pull of AstraZeneca data updates to git repository"

cd $AZ_DATA_HOME ; $GIT_BINARY pull origin

if [ $? -gt 0 ] ; then
    sendPreImportFailureMessageMskPipelineLogsSlack "GIT PULL (az-msk-impact-2022) :fire: - address ASAP!"

    EMAIL_BODY="Failed to pull AstraZeneca incoming changes from Git - address ASAP!"
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" | mail -s "[URGENT] GIT PUSH FAILURE" $PIPELINES_EMAIL_LIST

    exit 1
fi

# ------------------------------------------------------------------------------------------------------------------------
# 2. Copy data from local clone of MSK Solid Heme repo to local clone of AZ repo

cp -r $MSK_SOLID_HEME_DATA_HOME $AZ_MSK_IMPACT_DATA_HOME

if [ $? -gt 0 ] ; then
    echo "ERROR! Failed to copy MSK-IMPACT data to AstraZeneca repo. Skipping subset, merge, and update of AstraZeneca MSK-IMPACT!"
    sendPreImportFailureMessageMskPipelineLogsSlack "Copy MSK-IMPACT data to AstraZeneca repo"

    EMAIL_BODY="Failed to copy MSK-IMPACT data to AstraZeneca repo. Subset study will not be updated."
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" | mail -s "MSK-IMPACT Data Copy Failure: Study will not be updated." $PIPELINES_EMAIL_LIST

    exit 1
fi

# ------------------------------------------------------------------------------------------------------------------------
# 3. Remove Part C non-consented patients + samples
printTimeStampedDataProcessingStepMessage "subset and merge of MSK-IMPACT Part C Consented patients for AstraZeneca"

# Create temporary directory to store subset file
if ! [ -d "$AZ_TMPDIR" ] ; then
    if ! mkdir -p "$AZ_TMPDIR" ; then
        echo "Error : could not create tmp directory '$AZ_TMPDIR'" >&2
        exit 1
    fi
fi
if [[ -d "$AZ_TMPDIR" && "$AZ_TMPDIR" != "/" ]] ; then
    rm -rf "$AZ_TMPDIR"/*
fi

# Generate subset of Part C consented patients from MSK-Impact
$PYTHON_BINARY $PORTAL_HOME/scripts/generate-clinical-subset.py \
    --study-id="mskimpact" \
    --clinical-file="$AZ_MSK_IMPACT_DATA_HOME/data_clinical_patient.txt" \
    --filter-criteria="PARTC_CONSENTED_12_245=YES" \
    --subset-filename="$AZ_TMPDIR/az_msk_impact_subset.txt"

if [ $? -gt 0 ] ; then
    echo "ERROR! Failed to generate subset of MSK-IMPACT for AstraZeneca. Skipping merge and update of AstraZeneca MSK-IMPACT!"
    sendPreImportFailureMessageMskPipelineLogsSlack "AstraZeneca subset generation from MSK-IMPACT"

    EMAIL_BODY="Failed to subset AstraZeneca MSK-IMPACT data. Subset study will not be updated."
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" | mail -s "AstraZeneca MSK-IMPACT Subset Failure: Study will not be updated." $PIPELINES_EMAIL_LIST

    exit 1
fi

# Write out the subsetted data
$PYTHON_BINARY $PORTAL_HOME/scripts/merge.py \
    --study-id="mskimpact" \
    --subset="$AZ_TMPDIR/az_msk_impact_subset.txt" \
    --output-directory="$AZ_MSK_IMPACT_DATA_HOME" \
    --merge-clinical="true" \
    $AZ_MSK_IMPACT_DATA_HOME

if [ $? -gt 0 ] ; then
    echo "Error! Failed to merge subset of MSK-IMPACT for AstraZeneca. Skipping update of AstraZeneca MSK-IMPACT!"
    sendPreImportFailureMessageMskPipelineLogsSlack "AstraZeneca subset merge from MSK-IMPACT"

    EMAIL_BODY="Failed to merge subset of MSK-IMPACT for AstraZeneca"
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" |  mail -s "AstraZeneca MSK-IMPACT Merge Failure: Study will not be updated." $PIPELINES_EMAIL_LIST

    exit 1

# Remove temporary directory now that the subset has been merged
rm -rf "$AZ_TMPDIR"

# ------------------------------------------------------------------------------------------------------------------------
# 4. Run changelog script
printTimeStampedDataProcessingStepMessage "generate changelog for AstraZeneca MSK-IMPACT updates"

# TODO Should the output file go to a specific directory/filename?
$PYTHON3_BINARY $PORTAL_HOME/scripts/changelog.py $AZ_MSK_IMPACT_DATA_HOME

if [ $? -gt 0 ] ; then
    echo "Error! Failed to generate changelog summary for AstraZeneca MSK-Impact subset."
    sendPreImportFailureMessageMskPipelineLogsSlack "AstraZeneca MSK-IMPACT changelog generation "

    EMAIL_BODY="Failed to generate changelog summary for AstraZeneca MSK-Impact subset"
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" |  mail -s "AstraZeneca MSK-IMPACT Changelog Failure: Changelog summary will not be provided." $PIPELINES_EMAIL_LIST

# TODO Should data still be pushed if changelog script fails?

# ------------------------------------------------------------------------------------------------------------------------
# 5. Push the updates data to GitHub
printTimeStampedDataProcessingStepMessage "push of AstraZeneca data updates to git repository"

cd $AZ_DATA_HOME ; $GIT_BINARY push origin

if [ $? -gt 0 ] ; then
    sendPreImportFailureMessageMskPipelineLogsSlack "GIT PUSH (az-msk-impact-2022) :fire: - address ASAP!"

    EMAIL_BODY="Failed to push AstraZeneca MSK-IMPACT outgoing changes to Git - address ASAP!"
    echo -e "Sending email $EMAIL_BODY"
    echo -e "$EMAIL_BODY" |  mail -s "[URGENT] GIT PUSH FAILURE" $PIPELINES_EMAIL_LIST

    exit 1
fi

