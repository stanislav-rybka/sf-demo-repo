# Authorization into SF environment by provided org credentials
# $1 param - target org username
# $2 param - target org password
# $3 param - target org login URL
# $4 param - target org alias
function authorizeWithCredentials {

    local TARGET_ORG_USERNAME=$1
    local TARGET_ORG_PASSWORD=$2
    local TARGET_ORG_URL=$3
    local TARGET_ORG_ALIAS=$4

    if [[ -z "$TARGET_ORG_USERNAME" || "$TARGET_ORG_USERNAME" == "none" || \
          -z "$TARGET_ORG_PASSWORD" || "$TARGET_ORG_PASSWORD" == "none" || \
          -z "$TARGET_ORG_URL" || "$TARGET_ORG_URL" == "none" ]]; then

      echo "❌ Target environment credentials are not completely provided. Cannot continue the authorization process."
      exit 1;

    fi

    echo "⏳ Authorizing to the target environment..."

    # temporary disabling immediate exit by using "set +e/-e" commands (i.e. some kind of try/catch)
    set +e

    local DX_AUTH_RESPONSE=$(sf sfpowerkit:auth:login \
        -u "$TARGET_ORG_USERNAME" \
        -p "$TARGET_ORG_PASSWORD" \
        -a "$TARGET_ORG_ALIAS" \
        -r "$TARGET_ORG_URL" \
        --json)

    local DX_STATUS_CODE=$(echo "$DX_AUTH_RESPONSE" | jq .status)
    
    set -e

    # early exit - error when authorizing to target org by creds
    if [[ "$DX_STATUS_CODE" != "0" ]]; then

      echo "❌ Error when logging into the target environment by provided credentials as '$TARGET_ORG_USERNAME' user."
      echo "$DX_AUTH_RESPONSE" | jq .message
      exit 1;

    fi

    echo ""
    echo "✅ Successfully authorized as '$TARGET_ORG_USERNAME' user"

    # setting target org alias at runner's level for other steps.
    echo "TARGET_ORG_USERNAME=$TARGET_ORG_USERNAME" >> $GITHUB_ENV

}


# Authorization into SF environment by provided org authorization URL
# $1 param - target org authorization URL
# $2 param - target org alias
function authorizeWithAuthUrl {

    local TARGET_ORG_AUTH_URL=$1
    local TARGET_ORG_ALIAS=$2

    # temporary disabling immediate exit by using "set +e/-e" commands (i.e. some kind of try/catch)
    set +e

    local DX_AUTH_RESPONSE=$(echo $TARGET_ORG_AUTH_URL | sf org login sfdx-url --sfdx-url-stdin --json -a "$TARGET_ORG_ALIAS");
    local DX_STATUS_CODE=$(echo $DX_AUTH_RESPONSE | jq .status);

    set -e

    # early exit - error when authorizing to target environment
    if [[ "$DX_STATUS_CODE" != "0" ]]; then

      echo "❌ Error when logging into the target environment ('$TARGET_ORG_ALIAS') by SFDX URL."
      echo "$DX_AUTH_RESPONSE" | jq .
      exit 1

    fi

    local TARGET_ORG_USERNAME=$(echo "$DX_AUTH_RESPONSE" | jq -r '.result.username // empty');

    echo ""
    echo "✅ Successfully authorized as '$TARGET_ORG_USERNAME' user"
    
    # setting target org alias at runner's level for other steps.
    echo "TARGET_ORG_USERNAME=$TARGET_ORG_USERNAME" >> $GITHUB_ENV

}