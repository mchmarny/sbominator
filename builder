#!/bin/bash

set -o errexit

# image ref (tag or sha)
IMAGE=$1

msg(){ echo "
${1}
-------------------------------------------------------------------------------
";}

echo "
===============================================================================
loud Build SBOM Builder
===============================================================================
"

msg "Validating input"

# check required input parameters
[ -z "$IMAGE" ] && echo "image not provided\n" && exit 1
[ -z "$PROJECT" ] && echo "env var PROJECT not set (e.g. my-project-id)\n" && exit 1
[ -z "$REGISTRY" ] && echo "env var REGISTRY not set (e.g. us-west1-docker.pkg.dev)\n" && exit 1
[ -z "$KEY" ] && echo "env var KEY not set (e.g. projects/project/locations/us-west1/keyRings/mykey/cryptoKeys/img-signer/cryptoKeyVersions/1)\n" && exit 1


echo "PROJECT:  $PROJECT"
echo "REGISTRY: $REGISTRY"
echo "IMAGE:    $IMAGE"
echo "KEY:      $KEY"
echo "VERSION:  $VERSION" # optional
echo "COMMIT:   $COMMIT"  # optional
echo "SCAN:     $SCAN"  # optional

msg "Configururing builder"
gcloud auth configure-docker $REGISTRY --quiet
gcloud config set project $PROJECT

KEY="gcpkms://${KEY}"
cosign generate-key-pair --kms $KEY

msg "Signing container image"

VERSION_ARG=""
if [ -z "$VERSION_ARG" ]
then
      echo "VERSION not set, skipping"
else
      VERSION_ARG="-a version=$VERSION"
fi

COMMIT_ARG=""
if [ -z "$COMMIT_ARG" ]
then
      echo "COMMIT not set, skipping"
else
      COMMIT_ARG="-a commit=$COMMIT"
fi

cosign sign --key $KEY $VERSION_ARG $COMMIT_ARG $IMAGE
cosign verify --key $KEY $IMAGE

msg "Generating SBOM from image and publish attestation"
syft --scope all-layers -o spdx-json=sbom.spdx.json $IMAGE | jq --compact-output > sbom.spdx.json
cosign attest --predicate sbom.spdx.json --key $KEY $IMAGE

if [ -n "${SCAN}" ]; then
    msg "Scan for vulnerabilities using SBOM"
    grype --add-cpes-if-none sbom:sbom.spdx.json -o json | jq --compact-output > vulns.grype.json
    cat vulns.grype.json

    msg "Uploading vulnerabilities report to registry"
    SHA_TAG=$(echo $IMAGE | tr ':' '-' | tr '@' ':')
    VULN_TAG="${SHA_TAG}.vuln"
    cosign upload blob -f sbom.spdx.json $VULN_TAG

    msg "Signing vulnerabilities report"
    cosign sign --key $KEY $VULN_TAG
    cosign verify --key $KEY $VULN_TAG
fi

echo "DONE"



