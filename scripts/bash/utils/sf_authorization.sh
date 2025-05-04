#!/bin/bash

# --------------------
# Function to authorize into SF environment by provided org credentials
# --------------------
function authorize_with_credentials {

    local target_org_username=$1
    local target_org_password=$2
    local target_org_url=$3
    local target_org_alias=$4

    if [[ -z "$target_org_username" || "$target_org_username" == "none" || \
          -z "$target_org_password" || "$target_org_password" == "none" || \
          -z "$target_org_url" || "$target_org_url" == "none" ]]; then

      echo "❌ ERROR: Target environment credentials are not provided, cannot continue the authorization process."
      exit 1;

    fi

    echo "⏳ Authorizing to the target environment..."

    # Temporary disabling immediate exit by using "set +e/-e" commands (i.e. some kind of try/catch)
    set +e

    local dx_auth_response=$(sf sfpowerkit:auth:login \
        -u "$target_org_username" \
        -p "$target_org_password" \
        -a "$target_org_alias" \
        -r "$target_org_url" \
        --json)

    local dx_status_code=$(echo "$dx_auth_response" | jq .status)
    
    set -e

    # Early exit - error when authorizing to target org by creds
    if [[ "$dx_status_code" != "0" ]]; then

      echo "❌ ERROR: failure when logging into the target environment by provided credentials as '$target_org_username' user."
      echo "$dx_auth_response" | jq .message
      exit 1;

    fi

    echo ""
    echo "✅ Successfully authorized as '$target_org_username' user."

    # Setting target org alias at runner's level for other steps.
    echo "TARGET_ORG_USERNAME=$target_org_username" >> $GITHUB_ENV

}

# --------------------
# Authorization into SF environment by provided org authorization URL
# --------------------
function authorize_with_auth_url {

    local target_org_auth_url=$1
    local target_org_alias=$2

    # Temporary disabling immediate exit by using "set +e/-e" commands (i.e. some kind of try/catch)
    set +e

    local dx_auth_response=$(echo $target_org_auth_url | sf org login sfdx-url --sfdx-url-stdin --json -a "$target_org_alias");
    local dx_status_code=$(echo $dx_auth_response | jq .status);

    set -e

    # Early exit - error when authorizing to target environment
    if [[ "$dx_status_code" != "0" ]]; then

      echo "❌ ERROR: failure when logging into the target environment ('$target_org_alias') by SFDX URL."
      echo "$dx_auth_response" | jq .
      exit 1

    fi

    local target_org_username=$(echo "$dx_auth_response" | jq -r '.result.username // empty');

    echo ""
    echo "✅ Successfully authorized as '$target_org_username' user."
    
    # Setting target org alias at runner's level for other steps.
    echo "TARGET_ORG_USERNAME=$target_org_username" >> $GITHUB_ENV

}