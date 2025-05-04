#!/bin/bash

# Allowed values
ALLOWED_DEPLOYMENT_MODES=("validateOnly" "validateWithTests" "deploy" "preview")
ALLOWED_DEPLOYMENT_TYPES=("full" "delta")

# Set variables with default values
TARGET_ORG="target-org-alias"
DEPLOYMENT_TYPE="delta"
DEPLOYMENT_MODE="validateWithTests"
SOURCE_DIR="force-app"
SOURCE_BRANCH="origin/develop"
DEST_BRANCH="HEAD"
ARTIFACTS_OUTPUT_DIR_PATH="scripts/deployment/artifacts"

########################## FUNCTIONS (BEGIN)

# --------------------
# Function to validate provided script inputs
# --------------------
function validate_inputs {

    # Check if sf CLI is installed
    if ! command -v sf &> /dev/null; then
        echo "❌ ERROR: Salesforce CLI (sf) is not installed. Please install it first."
        exit 1
    fi

    # Check if deployment mode is valid
    if [[ ! " ${ALLOWED_DEPLOYMENT_MODES[@]} " =~ " ${DEPLOYMENT_MODE} " ]]; then
        echo "❌ ERROR: Invalid deployment mode: '${DEPLOYMENT_MODE}'."
        echo "ⓘ Allowed values: 'validateOnly', 'validateWithTests', 'deploy', 'preview'."
        exit 1
    fi

    # Check if deployment type is valid
    if [[ ! " ${ALLOWED_DEPLOYMENT_TYPES[@]} " =~ " ${DEPLOYMENT_TYPE} " ]]; then
        echo "❌ ERROR: Invalid deployment type: '${DEPLOYMENT_TYPE}'."
        echo "ⓘ Allowed values: 'full', 'delta'."
        exit 1
    fi

}

# --------------------
# Function to perform deployment of all metadata files located in provided source directory
# --------------------
function deploy_all_metadata {

    local deploy_manifest_path="${ARTIFACTS_OUTPUT_DIR_PATH}/package.xml"

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

    # Deploy FULL metadata
    deploy_metadata "$DEPLOYMENT_MODE" "$deploy_manifest_path"

}

# --------------------
# Function to perform deployment of only changed metadata files
# --------------------
function deploy_delta_metadata {

    local deploy_manifest_path="${ARTIFACTS_OUTPUT_DIR_PATH}/package/package.xml"
    local destructive_manifest_path="${ARTIFACTS_OUTPUT_DIR_PATH}/destructiveChanges/destructiveChanges.xml"

    echo "👀 Comparing changes from '$SOURCE_BRANCH' to '$DEST_BRANCH' branches..."

    # Generate package.xml and destructiveChanges.xml files containing only modified files (i.e. delta)
    sf sgd source delta \
        -o "$ARTIFACTS_OUTPUT_DIR_PATH" \
        --to "$DEST_BRANCH" \
        --from "$(git merge-base HEAD $SOURCE_BRANCH)"

    # Check if files generation failed
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: 'package.xml'/'destructiveChanges.xml' files generation failed."
        exit 1
    fi

    # If destructive changes SHOULD be included into deployment operation, use the line below
    # deploy_metadata "$deploy_manifest_path" "$destructive_manifest_path"

    # If destructive changes SHOULD NOT be included into deployment operation, use the line below
    deploy_metadata "$deploy_manifest_path"

}

# --------------------
# Function to perform actual metadata deployment
# --------------------
function deploy_metadata {

    local deploy_manifest_path="$1"
    local destructive_manifest_path="$2"
    local test_level="$3"
    local destructive_deployment="disabled"
    local dry_run_flag=""
    local destructive_flag=""

    # Print deployment artifacts content
    print_deployment_metadata "$deploy_manifest_path" "🔹 📦 Metadata to be DEPLOYED:"

    # Stop deployment processing if the deployment mode is 'preview'
    if [[ "$DEPLOYMENT_MODE" == "preview" ]]; then
        echo "✅ Deployment preview is completed."
        return
    fi

    # Check if the test level is provided, and if not - apply the corresponding value
    if [[ -z "$test_level" ]]; then
        if [[ "$DEPLOYMENT_MODE" == "validateOnly" ]]; then
            test_level="NoTestRun"
        else
            test_level="RunLocalTests"
        fi
    fi

    # Add --dry-run flag for "validateOnly" and "validateWithTests" deployment modes
    if [[ "$DEPLOYMENT_MODE" == "validateOnly" || "$DEPLOYMENT_MODE" == "validateWithTests" ]]; then
        dry_run_flag="--dry-run"
    fi

    # Add --post-destructive-changes flag only when destructive deployment is enabled
    if [[ -n "$destructive_manifest_path" ]]; then
        destructive_deployment="enabled"
        destructive_flag="--post-destructive-changes $destructive_manifest_path"

        # Print destructive artifacts content
        print_deployment_metadata "$destructive_manifest_path" "🗑 ❌ Metadata to be DELETED:"
    fi

    # Print deployment params
    echo "🚀 Deployment Params:"
    echo "--------------------------"
    echo "🟣 Deployment Type: '$DEPLOYMENT_TYPE'"
    echo "🟣 Deployment Mode: '$DEPLOYMENT_MODE'"
    echo "🟣 Test Level: '$test_level'"
    echo "🟣 Destructive Deployment: $destructive_deployment"
    echo "--------------------------"
    echo "⏳ Starting deployment to '$TARGET_ORG'..."

    # Start metadata deployment
    sf project deploy start \
        -o "$TARGET_ORG" \
        -x "$deploy_manifest_path" \
        $destructive_flag \
        --ignore-conflicts \
        --ignore-warnings \
        --test-level="$test_level" \
        -w 1000 \
        --junit \
        --concise \
        $dry_run_flag
    
}

# --------------------
# Function to extract and format metadata from XML (package.xml / desctructiveChanges.xml)
# --------------------
function print_deployment_metadata {

    local file_path="$1"
    local header="$2"
    local output=""

    if [ ! -f "$file_path" ]; then
        echo "$header"
        echo "ⓘ No metadata XML file is found by provided path."
        return
    fi

    echo "$header"
    echo "--------------------------------------------------------"

    output=$(awk '
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
    ' "$file_path")

    # Check if output is empty
    if [ -z "$output" ]; then
        output="ⓘ No metadata entries are found in the XML file."
    fi
    
    echo "$output"
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
validate_inputs

# Additional safeguard if deployment mode is "deploy" to prevent accident deployments
if [[ "$DEPLOYMENT_MODE" == "deploy" ]]; then
    echo "ⓘ You are about to DEPLOY. Are you sure you want to continue? (y/n)?"
    read -r confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo "❌ ERROR: Deployment aborted."
        exit 1
    fi
fi

# Ensure the artifacts output directory exists
mkdir -p "$ARTIFACTS_OUTPUT_DIR_PATH"

# Check if the metadata should be deployed fully or partially
if [[ "$DEPLOYMENT_TYPE" == "full" ]]; then
    deploy_all_metadata
else
    deploy_delta_metadata
fi

########################## MAIN (END)