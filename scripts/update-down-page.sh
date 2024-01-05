#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

print_usage() {
  echo
  echo "Usage: update-down-page.sh <environment> <index-html-file>"
  echo "<environment> can be dev, qa, staging or prod - required"
  echo "<index-html-path> is the path of the new index.html file"
  echo
  echo "Uses your default AWS profile. To change the profile, set the AWS_DEFAULT_PROFILE environment variable"
  echo
  echo "Example: AWS_DEFAULT_PROFILE=other_account_profile deploy-deployer.sh dev 1.13.0-rc.1-bfd70e7"
}

UPDATE_ENV="${1-''}"
INDEX_HTML_PATH="${2-'index.html'}"
BUCKET_NAME=dockstore-ui-down

if [ -z "$UPDATE_ENV" ] || [ ! -f "$INDEX_HTML_PATH" ]; then
  print_usage
  exit 1
fi

if [ $UPDATE_ENV == "dev" ]; then
  export BUCKET_DIR="develop"
  export AWS_DEFAULT_REGION="us-east-1"
elif [ $UPDATE_ENV == "staging" ]; then
  export BUCKET_DIR="production"
  export AWS_DEFAULT_REGION="us-west-2"
elif [ $UPDATE_ENV == "qa" ]; then
  export BUCKET_DIR="develop"
  export AWS_DEFAULT_REGION="us-east-2"
elif [ $UPDATE_ENV == "prod" ]; then
  export BUCKET_DIR="production"
  export AWS_DEFAULT_REGION="us-east-1"
else
  echo "Invalid environment $UPDATE_ENV; must be dev, qa, staging or prod"
  print_usage
  exit 1
fi

INDEX_HTML="$(cat $INDEX_HTML_PATH)"
WEBACL_NAME="WebACL-${UPDATE_ENV}-down"

echo "UPDATE_ENV $UPDATE_ENV"
echo "BUCKET_NAME $BUCKET_NAME"
echo "BUCKET_DIR $BUCKET_DIR"
echo "INDEX_HTML_PATH $INDEX_HTML_PATH"
echo "INDEX_HTML $INDEX_HTML"
echo "WEBACL_NAME $WEBACL_NAME"

WEBACLS="$(aws wafv2 list-web-acls --scope REGIONAL)"
WEBACL_SUMMARY="$(echo "$WEBACLS" | jq '.WebACLs' | jq "map(select(.Name == \"${WEBACL_NAME}\"))" | jq '.[0]')"
WEBACL_ID="$(echo "$WEBACL_SUMMARY" | jq -r .Id)"
WEBACL_NAME="$(echo "$WEBACL_SUMMARY" | jq -r .Name)"
WEBACL_AND_LOCKTOKEN="$(aws wafv2 get-web-acl --scope REGIONAL --id "$WEBACL_ID" --name "$WEBACL_NAME")"
echo "WEBACL_AND_LOCKTOKEN ${WEBACL_AND_LOCKTOKEN}"
WEBACL="$(echo "$WEBACL_AND_LOCKTOKEN" | jq '.WebACL')"
WEBACL_LOCKTOKEN="$(echo "$WEBACL_AND_LOCKTOKEN" | jq '.LockToken')"
WEBACL_MODIFIED="$(echo "$WEBACL" | jq --rawfile html "${INDEX_HTML_PATH}" '.CustomResponseBodies["response"].Content = $html')"
echo "WEBACL_MODIFIED ${WEBACL_MODIFIED}"
WEBACL_SKELETON="$(aws wafv2 update-web-acl --generate-cli-skeleton)"
WEBACL_UPDATE="$(echo "$WEBACL_MODIFIED" | jq '.Scope = "REGIONAL" | .LockToken = '"${WEBACL_LOCKTOKEN}"' | '"$(echo "${WEBACL_SKELETON}" | jq 'keys' | tr '[]' '{}')")"
echo "WEBACL_UPDATE ${WEBACL_UPDATE}"
aws wafv2 update-web-acl --cli-input-json "${WEBACL_UPDATE}"
# zzz

# add s3 copy
