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

INDEX_HTML="$(cat $INDEX_HTML_PATH)"

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
  echo "Invalid environment $UPDATE_ENV; must be dev, qa, staging, or prod"
  print_usage
  exit 1
fi


WEBACL_NAME="WebACL-${UPDATE_ENV}-down"
echo "Updating WebACL '${WEBACL_NAME}' using content from '${INDEX_HTML_PATH}'."

# Retrieve a list of WebACLs and extract the summary by name.
WEBACL_SUMMARY="$(aws wafv2 list-web-acls --scope REGIONAL | jq '.WebACLs' | jq "map(select(.Name == \"${WEBACL_NAME}\"))" | jq '.[0]')"
if [[ "${WEBACL_SUMMARY}" == "null" ]]; then
  echo "Could not find WebACL '${WEBACL_NAME}'."
  echo "Exiting."
  exit 1
fi

# Extract the ID.
WEBACL_ID="$(echo "${WEBACL_SUMMARY}" | jq -r .Id)"

# Retrieve the full WebACL and associated lock token.
WEBACL_AND_LOCKTOKEN="$(aws wafv2 get-web-acl --scope REGIONAL --id "${WEBACL_ID}" --name "${WEBACL_NAME}")"
WEBACL="$(echo "${WEBACL_AND_LOCKTOKEN}" | jq '.WebACL')"
WEBACL_LOCKTOKEN="$(echo "${WEBACL_AND_LOCKTOKEN}" | jq '.LockToken')"

# Change the custom response body to the new content.
WEBACL_MODIFIED="$(echo "${WEBACL}" | jq --rawfile html "${INDEX_HTML_PATH}" '.CustomResponseBodies["response"].Content = $html')"

# Retrieve the AWS-suggested skeletion of the update json.
WEBACL_SKELETON="$(aws wafv2 update-web-acl --generate-cli-skeleton)"

# Add "Scope" and "LockToken" fields to the modified WebACL json, then remove any fields that don't appear in the skeleton.
# We must remove fields that don't appear in the skeleton because AWS rejects updates that include them.
WEBACL_UPDATE="$(echo "${WEBACL_MODIFIED}" | jq '.Scope = "REGIONAL" | .LockToken = '"${WEBACL_LOCKTOKEN}"' | '"$(echo "${WEBACL_SKELETON}" | jq 'keys' | tr '[]' '{}')")"

# Update the WebACL.
aws wafv2 update-web-acl --cli-input-json "${WEBACL_UPDATE}"
echo "Updated WebACL."


BUCKET_S3="s3://${BUCKET_NAME}/${BUCKET_DIR}/index.html"
echo "Updating down content S3 object '${BUCKET_S3}' using content from '${INDEX_HTML_PATH}'."

# Update the down content bucket.
aws s3 cp "${INDEX_HTML_PATH}" "${BUCKET_S3}"
echo "Updated bucket content."
