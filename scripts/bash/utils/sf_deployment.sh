#!/bin/bash

# Allowed values
ALLOWED_DEPLOYMENT_MODES=("validateOnly" "validateWithTests" "deploy" "preview")
ALLOWED_DEPLOYMENT_TYPES=("full" "delta")

# Set variables with default values
TARGET_ORG="target-org-alias"
DEPLOYMENT_MODE="validateWithTests"
SOURCE_BRANCH="origin/develop"
DEST_BRANCH="HEAD"
ARTIFACTS_OUTPUT_DIR_PATH="scripts/deployment/artifacts"

########################## FUNCTIONS (BEGIN)

function deployAllMetadata {
    local DEPLOY_MANIFEST_PATH="${ARTIFACTS_OUTPUT_DIR_PATH}/package.xml"

    # Generate package.xml file containing all files
    sf project generate manifest \
        -p force-app \
        -n "package" \
        -d "$ARTIFACTS_OUTPUT_DIR_PATH" \
        -t package

    # Check if the command was unsuccessful
    if [ $? -ne 0 ]; then
        echo "❌ Package.xml generation failed."
        exit 1
    fi

    # Print artifacts content
    printDeploymentMetadata "$DEPLOY_MANIFEST_PATH" "🔹 📦 Metadata to be DEPLOYED:"

    echo "⏳ Starting full deployment to $TARGET_ORG..."

    if [[ "${DEPLOYMENT_MODE}" == "validateOnly" ]] ; then

        deployMetadata "validateOnly" "NoTestRun" "$DEPLOY_MANIFEST_PATH"
        echo "✅ Metadata deployment validation without tests is successfully completed"

    elif [[ "${DEPLOYMENT_MODE}" == "validateWithTests" ]] ; then

        deployMetadata "validateWithTests" "RunLocalTests" "$DEPLOY_MANIFEST_PATH"
        echo "✅ Metadata deployment validation with tests is successfully completed"

    elif [[ "${DEPLOYMENT_MODE}" == "deploy" ]] ; then

        deployMetadata "deploy" "RunLocalTests" "$DEPLOY_MANIFEST_PATH"
        echo "✅ Metadata deployment is successfully completed"

    fi
}

function deployDeltaMetadata {
    local DEPLOY_MANIFEST_PATH="${ARTIFACTS_OUTPUT_DIR_PATH}/package/package.xml"
    local DESTRUCTIVE_MANIFEST_PATH="${ARTIFACTS_OUTPUT_DIR_PATH}/destructiveChanges/destructiveChanges.xml"

    # Generate package.xml and destructiveChanges.xml files containing only modified files (i.e. delta)
    echo "👀 Comparing changes from $SOURCE_BRANCH to $DEST_BRANCH..."

    sf sgd source delta \
        -o "$ARTIFACTS_OUTPUT_DIR_PATH" \
        --to "$DEST_BRANCH" \
        --from "$(git merge-base HEAD $SOURCE_BRANCH)"

    # Check if the command was unsuccessful
    if [ $? -ne 0 ]; then
        echo "❌ Delta generation failed."
        exit 1
    fi

    # Print artifacts content
    printDeploymentMetadata "$DEPLOY_MANIFEST_PATH" "🔹 📦 Metadata to be DEPLOYED:"
    printDeploymentMetadata "$DESTRUCTIVE_MANIFEST_PATH" "🗑 ❌ Metadata to be DELETED (Feature Temporarily Disabled):"

    # Deploy changes
    if [[ "${DEPLOYMENT_MODE}" == "preview" ]] ; then
        echo "✅ Preview is completed."
        exit 0
    fi

    echo "⏳ Starting delta deployment to $TARGET_ORG..."

    if [[ "${DEPLOYMENT_MODE}" == "validateOnly" ]] ; then

        deployMetadata "validateOnly" "NoTestRun" "$DEPLOY_MANIFEST_PATH" "$DESTRUCTIVE_MANIFEST_PATH"
        echo "✅ Metadata deployment validation without tests is successfully completed"

    elif [[ "${DEPLOYMENT_MODE}" == "validateWithTests" ]] ; then

        deployMetadata "validateWithTests" "RunLocalTests" "$DEPLOY_MANIFEST_PATH" "$DESTRUCTIVE_MANIFEST_PATH"
        echo "✅ Metadata deployment validation with tests is successfully completed"

    elif [[ "${DEPLOYMENT_MODE}" == "deploy" ]] ; then

        deployMetadata "deploy" "RunLocalTests" "$DEPLOY_MANIFEST_PATH" "$DESTRUCTIVE_MANIFEST_PATH"
        echo "✅ Metadata deployment is successfully completed"

    fi
}

# Function to extract and format metadata from XML
function printDeploymentMetadata {
    local FILE_PATH="$1"
    local HEADER="$2"

    if [ ! -f "$FILE_PATH" ]; then

        echo "$HEADER"
        echo "No metadata detected."
        return

    fi

    echo "$HEADER"
    echo "--------------------------------------------------------"

    local OUTPUT=$(awk '
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
        echo "No metadata entries are found..."
    else
        echo "$OUTPUT"
    fi

    echo ""
}

# Function to deploy metadata
function deployMetadata {
    local DEPLOY_MODE="$1"
    local TEST_LEVEL="$2"
    local DEPLOY_MANIFEST_PATH="$3"
    local DESTRUCTIVE_MANIFEST_PATH="$4"
    local DRY_RUN_FLAG=""

    # Add --dry-run flag for "validateOnly" and "validateWithTests" deployment modes
    if [[ "$DEPLOY_MODE" == "validateOnly" || "$DEPLOY_MODE" == "validateWithTests" ]]; then
        DRY_RUN_FLAG="--dry-run"
    fi

    # Temporarily disabled destructiveChanges.xml deployment
    # --post-destructive-changes "$DESTRUCTIVE_MANIFEST_PATH" \
    sf project deploy start \
        -o "$TARGET_ORG" \
        -x "$DEPLOY_MANIFEST_PATH" \
        --ignore-conflicts \
        --ignore-warnings \
        --test-level="$TEST_LEVEL" \
        -w 1000 \
        --junit \
        --concise \
        $DRY_RUN_FLAG  # Include dry-run flag if applicable
}

########################## FUNCTIONS (END)

########################## MAIN (BEGIN)

# Parse command-line arguments
while getopts "o:s:d:m:t:h" opt; do
    case $opt in
        o) TARGET_ORG="$OPTARG" ;;  # Salesforce org alias/username
        s) SOURCE_BRANCH="$OPTARG" ;; # Git branch to compare from (previous state)
        d) DEST_BRANCH="$OPTARG" ;;  # Git branch to compare to (current state)
        m) DEPLOYMENT_MODE="$OPTARG" ;;  # Deployment mode
        t) DEPLOYMENT_TYPE="$OPTARG" ;; # Deployment type
        h) 
            echo "Usage: $0 [-o target_org] [-s source_branch] [-d dest_branch] [-m deployment_mode] [-t deployment_type]"
            exit 0
            ;;
        \?) echo "❌ Invalid option -$OPTARG" >&2; exit 1 ;;
    esac
done


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

# Additional safeguard if deployment mode is "deploy" to prevent accident deployments
if [[ "$DEPLOYMENT_MODE" == "deploy" ]]; then
    echo "⚠️  You are about to DEPLOY. Are you sure you want to continue? (yes/no)"
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