#!/bin/bash

# Allowed values
ALLOWED_DEPLOYMENT_MODES=("validateOnly" "validateWithTests" "deploy" "preview")
ALLOWED_DEPLOYMENT_TYPES=("full" "delta")

# Set variables with default values
TARGET_ORG="target-org-alias"
DEPLOYMENT_MODE="validateWithTests"
SOURCE_DIR="force-app"
SOURCE_BRANCH="origin/develop"
DEST_BRANCH="HEAD"
ARTIFACTS_OUTPUT_DIR_PATH="scripts/deployment/artifacts"

########################## FUNCTIONS (BEGIN)

# Function to validate provided script inputs.
function validateInputs {

    # Check if sf CLI is installed
    if ! command -v sf &> /dev/null; then

        echo "❌ ERROR: Salesforce CLI (sf) is not installed. Please install it first."
        exit 1

    fi

    # Check if deployment mode is valid
    if [[ ! " ${ALLOWED_DEPLOYMENT_MODES[@]} " =~ " ${DEPLOYMENT_MODE} " ]]; then

        echo "❌ ERROR: Invalid deployment mode: '${DEPLOYMENT_MODE}'."
        echo "➡ Allowed values: validateOnly, validateWithTests, deploy, preview"
        exit 1

    fi

    # Check if deployment type is valid
    if [[ ! " ${ALLOWED_DEPLOYMENT_TYPES[@]} " =~ " ${DEPLOYMENT_TYPE} " ]]; then

        echo "❌ ERROR: Invalid deployment type: '${DEPLOYMENT_TYPE}'."
        echo "➡ Allowed values: full, delta"
        exit 1

    fi

}


# Function to perform 
function deployAllMetadata {

    local DEPLOY_MANIFEST_PATH="${ARTIFACTS_OUTPUT_DIR_PATH}/package.xml"

    # Generate package.xml file containing all metadata entries from solution
    sf project generate manifest \
        -p "$SOURCE_DIR" \
        -n "package" \
        -d "$ARTIFACTS_OUTPUT_DIR_PATH"

    # Check if the command was unsuccessful
    if [ $? -ne 0 ]; then

        echo "❌ ERROR: 'package.xml' file generation failed."
        exit 1

    fi

    # Print artifacts content
    printDeploymentMetadata "$DEPLOY_MANIFEST_PATH" "🔹 📦 Metadata to be DEPLOYED:"

    # If provided deployment mode is 'preview', stop processing here
    if [[ "${DEPLOYMENT_MODE}" == "preview" ]] ; then

        echo "✅ Deployment preview is completed."
        return

    fi

    # Othewise, proceed with metadata deployment
    local TEST_LEVEL="RunLocalTests"

    if [[ "${DEPLOYMENT_MODE}" == "validateOnly" ]] ; then

        TEST_LEVEL="NoTestRun"

    fi

    echo "⏳ Starting FULL deployment to '$TARGET_ORG'..."

    deployMetadata "$DEPLOYMENT_MODE" "$TEST_LEVEL" "$DEPLOY_MANIFEST_PATH"

}


function deployDeltaMetadata {

    local DEPLOY_MANIFEST_PATH="${ARTIFACTS_OUTPUT_DIR_PATH}/package/package.xml"
    local DESTRUCTIVE_MANIFEST_PATH="${ARTIFACTS_OUTPUT_DIR_PATH}/destructiveChanges/destructiveChanges.xml"

    echo "👀 Comparing changes from '$SOURCE_BRANCH' to '$DEST_BRANCH' branches..."

    # Generate package.xml and destructiveChanges.xml files containing only modified files (i.e. delta)
    sf sgd source delta \
        -o "$ARTIFACTS_OUTPUT_DIR_PATH" \
        --to "$DEST_BRANCH" \
        --from "$(git merge-base HEAD $SOURCE_BRANCH)"

    # Check if files generation failed
    if [ $? -ne 0 ]; then

        echo "❌ ERROR: 'package.xml' / 'destructiveChanges.xml' files generation failed."
        exit 1

    fi

    # Print artifacts content
    printDeploymentMetadata "$DEPLOY_MANIFEST_PATH" "🔹 📦 Metadata to be DEPLOYED:"
    printDeploymentMetadata "$DESTRUCTIVE_MANIFEST_PATH" "🗑 ❌ Metadata to be DELETED:"

    # If provided deployment mode is 'preview', stop processing here
    if [[ "${DEPLOYMENT_MODE}" == "preview" ]] ; then

        echo "✅ Deployment preview is completed."
        return

    fi

    # Othewise, proceed with metadata deployment
    local TEST_LEVEL="RunLocalTests"

    if [[ "${DEPLOYMENT_MODE}" == "validateOnly" ]] ; then

        TEST_LEVEL="NoTestRun"

    fi

    echo "⏳ Starting DELTA deployment to '$TARGET_ORG'..."

    # If destructive changes SHOULD be included into deployment operation, use the line below
    # deployMetadata "$DEPLOYMENT_MODE" "$TEST_LEVEL" "$DEPLOY_MANIFEST_PATH" "$DESTRUCTIVE_MANIFEST_PATH"

    # If destructive changes SHOULD NOT be included into deployment operation, use the line below
    deployMetadata "$DEPLOYMENT_MODE" "$TEST_LEVEL" "$DEPLOY_MANIFEST_PATH"

}


# Function to perform metadata deployment
function deployMetadata {

    local DEPLOY_MODE="$1"
    local TEST_LEVEL="$2"
    local DEPLOY_MANIFEST_PATH="$3"
    local DESTRUCTIVE_MANIFEST_PATH="$4"
    local DESTRUCTIVE_DEPLOYMENT="disabled"
    local DRY_RUN_FLAG=""
    local DESTRUCTIVE_FLAG=""

    # Add --dry-run flag for "validateOnly" and "validateWithTests" deployment modes
    if [[ "$DEPLOY_MODE" == "validateOnly" || "$DEPLOY_MODE" == "validateWithTests" ]]; then

        DRY_RUN_FLAG="--dry-run"

    fi

    # Add --post-destructive-changes flag only when destructive deployment is enabled
    if [[ -n "$DESTRUCTIVE_MANIFEST_PATH" ]]; then

        DESTRUCTIVE_DEPLOYMENT="enabled"
        DESTRUCTIVE_FLAG="--post-destructive-changes $DESTRUCTIVE_MANIFEST_PATH"

    fi

    # Print deployment params
    echo "🚀 Deployment Params:"
    echo "--------------------------"
    echo "✅ Deployment Mode: '$DEPLOY_MODE'"
    echo "✅ Test Level: '$TEST_LEVEL'"
    echo "✅ Destructive Deployment: $DESTRUCTIVE_DEPLOYMENT"

    # Start metadata deployment
    sf project deploy start \
        -o "$TARGET_ORG" \
        -x "$DEPLOY_MANIFEST_PATH" \
        $DESTRUCTIVE_FLAG \
        --ignore-conflicts \
        --ignore-warnings \
        --test-level="$TEST_LEVEL" \
        -w 1000 \
        --junit \
        --concise \
        $DRY_RUN_FLAG  # Include dry-run flag if applicable
    
}


# Function to extract and format metadata from XML (package.xml / desctructiveChanges.xml)
function printDeploymentMetadata {

    local FILE_PATH="$1"
    local HEADER="$2"
    local OUTPUT=""

    if [ ! -f "$FILE_PATH" ]; then

        echo "$HEADER"
        echo "ⓘ No metadata XML file is found by provided path."
        return

    fi

    echo "$HEADER"
    echo "--------------------------------------------------------"

    OUTPUT=$(awk '
        BEGIN { counter = 1 }  # Initialize the global counter
        /<types>/ { inside_types = 1 } 
        /<\/types>/ { inside_types = 0 } 
        inside_types {
            if ($0 ~ /<members>/) {
                sub(".*<members>", "", $0); sub("</members>.*", "", $0);
                members[++m_count] = $0;
            }
            if ($0 ~ /<name>/) {
                sub(".*<name>", "", $0); sub("</name>.*", "", $0);
                type = $0;
                for (i = 1; i <= m_count; i++) {
                    # Use global counter instead of resetting it
                    printf "%5d  %s - %s\n", counter++, members[i], type;
                }
                m_count = 0; # Reset members count
            }
        }
    ' "$FILE_PATH")

    # Check if OUTPUT is empty
    if [ -z "$OUTPUT" ]; then

        OUTPUT="ⓘ No metadata entries are found in the XML file."

    fi
    
    echo "$OUTPUT"
    echo ""

}

########################## FUNCTIONS (END)

########################## MAIN (BEGIN)

# Parse command-line arguments
while getopts "o:p:s:d:m:t:h" opt; do
    case $opt in
        o) TARGET_ORG="$OPTARG" ;;  # Salesforce org alias/username
        p) SOURCE_DIR="$OPTARG" ;; # Source directory to take metadata files from
        s) SOURCE_BRANCH="$OPTARG" ;; # Git branch to compare from (previous state)
        d) DEST_BRANCH="$OPTARG" ;;  # Git branch to compare to (current state)
        m) DEPLOYMENT_MODE="$OPTARG" ;;  # Deployment mode
        t) DEPLOYMENT_TYPE="$OPTARG" ;; # Deployment type
        h) 
            echo "Usage: $0 [-o target_org] [-p source_dir] [-s source_branch] [-d dest_branch] [-m deployment_mode] [-t deployment_type]"
            exit 0
            ;;
        \?) echo "❌ Invalid option -$OPTARG" >&2; exit 1 ;;
    esac
done

# Validate parsed arguments
validateInputs

# Additional safeguard if deployment mode is "deploy" to prevent accident deployments
if [[ "$DEPLOYMENT_MODE" == "deploy" ]]; then

    echo "ⓘ You are about to DEPLOY. Are you sure you want to continue? (yes/no)"
    read -r confirm
    
    if [[ "$confirm" != "yes" ]]; then

        echo "❌ Deployment aborted."
        exit 1

    fi

fi

# Ensure the artifacts output directory exists
mkdir -p "$ARTIFACTS_OUTPUT_DIR_PATH"

# Check if the metadata should be deployed fully or partially
if [[ "$DEPLOYMENT_TYPE" == "full" ]]; then

    deployAllMetadata

else

    deployDeltaMetadata

fi

########################## MAIN (END)