#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

export ANTI_WAIT=180

unset ANTI_TOKEN_ID

log "Using ANTI_MPFS_HOST: $ANTI_MPFS_HOST"

log "Creating an anti token..."
result=$(anti oracle token boot)

tokenId=$(echo "$result" | jq -r '.result.value')
log "Anti token ID: $tokenId"

export ANTI_TOKEN_ID="$tokenId"

tokenEnd() {
    log "Ending anti token $ANTI_TOKEN_ID..."
    anti oracle token end >/dev/null || echo "Failed to end the token"
}
trap 'tokenEnd' EXIT INT TERM

log "Creating a registration user request..."

resultReg1=$(anti requester register-user \
    --platform github \
    --username cfhal \
    --pubkeyhash AAAAC3NzaC1lZDI1NTE5AAAAILjwzNvy87HbzYV2lsW3UjVoxtpq4Nrj84kjo3puarCH)

outputRegRef1=$(getOutputRef "$resultReg1")
log "Created registration request with valid public key with output reference: $outputRegRef1"

if [ -z "$GITHUB_PERSONAL_ACCESS_TOKEN" ]; then
    log "Error: GITHUB_PERSONAL_ACCESS_TOKEN is not set. Please refer to \"https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens\#creating-a-fine-grained-personal-access-token\""
    exit 1
fi

resultVal1=$(anti oracle requests validate | jq -r '.result')

expectedVal1=$(
    cat <<EOF
[
  {
    "reference": "$outputRegRef1",
    "validation": "validated"
  }
]
EOF
)

emitMismatch() {
    log "$2 result does not match expected value:"
    log "    Actual $2 $1 result: $3"
    log "    Expected $2 validation $1 result: $4"
    exit 1
}

if [[ "$(echo "$resultVal1" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal1" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 1 "validation" "$resultVal1" "$expectedVal1"
fi

resultReg2=$(anti requester register-user \
    --platform github \
    --username cfhal \
    --pubkeyhash AAAAC3NzaC1lZDI1NTE5AAAAILjwzNvy87HbzYV2lsW3UjVoxtpq4Nrj84djo3puarCH)

outputRegRef2=$(getOutputRef "$resultReg2")
log "Created registration request with invalid public key with output reference: $outputRegRef2"

resultVal2=$(anti oracle requests validate | jq -r '.result')

expectedVal2=$(
    cat <<EOF
[
  {
    "reference": "$outputRegRef1",
    "validation": "validated"
  },
  {
    "reference": "$outputRegRef2",
    "validation": "not validated: The user does not have the specified Ed25519 public key exposed in Github."
  }
]
EOF
)

if [[ "$(echo "$resultVal2" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal2" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 2 "validation" "$resultVal2" "$expectedVal2"
fi

log "Trying to register a role before token updating xxx"
resultRole1=$(anti requester register-role \
    --platform github \
    --repository cardano-foundation/hal-fixture-sin \
    --username cfhal \
    )
outputRoleRef1=$(getOutputRef "$resultRole1")

log "Created role registration request with output reference: $outputRoleRef1"
resultVal3=$(anti oracle requests validate | jq -r '.result')

expectedVal3=$(
    cat <<EOF
[
  {
    "reference": "$outputRegRef1",
    "validation": "validated"
  },
  {
    "reference": "$outputRegRef2",
    "validation": "not validated: The user does not have the specified Ed25519 public key exposed in Github."
  },
  {
    "reference": "$outputRoleRef1",
    "validation": "not validated: no registration for platform '\"github\"' and repository '\"hal-fixture-sin\"' of owner '\"cardano-foundation\"' and user '\"cfhal\"' found"
  }
]
EOF
)

if [[ "$(echo "$resultVal3" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal3" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 3 "validation" "$resultVal3" "$expectedVal3"
fi


log "Including the registration request that passed validation in the token ..."
anti oracle token update -o "$outputRegRef1" >/dev/null

printFacts

owner=$(anti wallet info | jq '.result.owner')

expectedGet1=$(
    cat <<EOF
[
  {
    "change": {
      "key": "{\"platform\":\"github\",\"publickeyhash\":\"AAAAC3NzaC1lZDI1NTE5AAAAILjwzNvy87HbzYV2lsW3UjVoxtpq4Nrj84kjo3puarCH\",\"type\":\"register-user\",\"user\":\"cfhal\"}",
      "type": "insert",
      "value": "null"
    },
    "outputRefId": "$outputRegRef2",
    "owner": $owner
  },
  {
    "change": {
      "key": "{\"platform\":\"github\",\"repository\":{\"organization\":\"cardano-foundation\",\"project\":\"hal-fixture-sin\"},\"type\":\"register-role\",\"user\":\"cfhal\"}",
      "type": "insert",
      "value": "null"
    },
    "outputRefId": "$outputRoleRef1",
    "owner": $owner
  }
]
EOF
)

resultGet1=$(anti oracle token get | jq '.result.requests')

if [[ "$(echo "$resultGet1" | jq -S 'sort_by(.outputRefId)')" != "$(echo "$expectedGet1" | jq -S 'sort_by(.outputRefId)')" ]]; then
    emitMismatch 4 "get token requests" "$resultGet1" "$expectedGet1"
fi

resultVal4=$(anti oracle requests validate | jq -r '.result')

expectedVal4=$(
    cat <<EOF
[
  {
    "reference": "$outputRegRef2",
    "validation": "not validated: The user does not have the specified Ed25519 public key exposed in Github."
  },
  {
    "reference": "$outputRoleRef1",
    "validation": "validated"
  }
]
EOF
)

if [[ "$(echo "$resultVal4" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal4" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 5 "validation" "$resultVal4" "$expectedVal4"
fi

log "Including the role request that passed validation in the token ..."
anti oracle token update -o "$outputRoleRef1" >/dev/null

printFacts

expectedGet2=$(
    cat <<EOF
[
  {
    "change": {
      "key": "{\"platform\":\"github\",\"publickeyhash\":\"AAAAC3NzaC1lZDI1NTE5AAAAILjwzNvy87HbzYV2lsW3UjVoxtpq4Nrj84kjo3puarCH\",\"type\":\"register-user\",\"user\":\"cfhal\"}",
      "type": "insert",
      "value": "null"
    },
    "outputRefId": "$outputRegRef2",
    "owner": $owner
  }
]
EOF
)

resultGet2=$(anti oracle token get | jq '.result.requests')

if [[ "$(echo "$resultGet2" | jq -S 'sort_by(.outputRefId)')" != "$(echo "$expectedGet2" | jq -S 'sort_by(.outputRefId)')" ]]; then
    emitMismatch 6 "get token requests" "$resultGet2" "$expectedGet2"
fi
