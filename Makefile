VERSION     ?=$(shell cat .version)
COMMIT      ?=$(shell git rev-parse --short HEAD)
PROJECT_ID  ?=cloudy-demos
REGION      ?=us
REG_URI     ?=$(REGION)-docker.pkg.dev
REG_PATH    ?=builders/sbom-builder
KMS_RING    ?=builder
KMS_KEY     ?=builder-signer
KMS_VERSION ?=1

# derived variables 
KEY_PATH    ?=$(KMS_RING)/cryptoKeys/$(KMS_KEY)/cryptoKeyVersions/$(KMS_VERSION)
SIGN_KEY    ?=gcpkms://projects/$(PROJECT_ID)/locations/$(REGION)/keyRings/$(KEY_PATH)
IMAGE_REG   ?=$(REG_URI)/$(PROJECT_ID)/$(REG_PATH)
IMAGE_URI   ?=$(IMAGE_REG):$(VERSION)
TEST_URI    ?=$(REG_URI)/$(PROJECT_ID)/$(REG_PATH)-test:$(VERSION)

all: help

version: ## Prints the current version
	@echo $(VERSION)
.PHONY: version

tag: ## Creates release tag 
	git tag -s -m "version bump to $(VERSION)" $(VERSION)
	git push origin $(VERSION)
.PHONY: tag

key: ## Build and publishes S3C tools
	@echo "Generating key-pair from: $(SIGN_KEY)"
	cosign generate-key-pair --kms $(SIGN_KEY)
.PHONY: key

builder: ## Build and publishes builder image
	@echo "\nBuild and push image"
	docker build -t $(IMAGE_URI) --platform linux/amd64 .
	docker push $(IMAGE_URI)

	@$(eval IMAGE_SHA=`docker inspect --format='{{index .RepoDigests 0}}' $(IMAGE_URI)`)
	@echo "IMAGE_SHA: $(IMAGE_SHA)\n"
	
	@echo "Sign and verify image"
	cosign sign --key $(SIGN_KEY) -a version=$(VERSION) -a commit=$(COMMIT) $(IMAGE_SHA)
	cosign verify --key $(SIGN_KEY) $(IMAGE_SHA)
	
	@echo "\nGenerate SBOM from image and publish attestation"
	syft --scope all-layers -o spdx-json=sbom.spdx.json $(IMAGE_SHA) \
		| jq --compact-output > sbom.spdx.json 
	cosign attest --predicate sbom.spdx.json --key $(SIGN_KEY) $(IMAGE_SHA)

.PHONY: builder


vulns: ## Outputs list of vulnerabilities 		
	grype --add-cpes-if-none sbom:sbom.spdx.json -o json \
		| jq --compact-output > vuln.grype.json
	cat vuln.grype.json | jq -r '["ID","DESCRIPTION"], (.matches[] | [ .vulnerability.id, .vulnerability.description ]) | @tsv'

.PHONY: builder

setup:
	gcloud kms keyrings create builder \
		--project $(PROJECT_ID) \
		--location $(REGION)

	gcloud kms keys create builder-signer \
		--project $(PROJECT_ID) \
		--location $(REGION) \
		--keyring builder \
		--purpose asymmetric-signing \
		--default-algorithm rsa-sign-pkcs1-4096-sha512

	gcloud kms keys describe builder-signer \
		--project $(PROJECT_ID) \
		--location $(REGION) \
		--keyring builder \
		--format json | jq --raw-output '.name'

.PHONY: setup 


help: ## Display available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk \
		'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.PHONY: help
