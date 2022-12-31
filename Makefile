VERSION     ?=$(shell cat .version)
COMMIT      ?=$(shell git rev-parse --short HEAD)
NAME        ?=sbominator
PROJECT_ID  ?=cloudy-demos
REGION      ?=us-west1
REG_URI     ?=$(REGION)-docker.pkg.dev
REG_PATH    ?=builders/$(NAME)
KMS_RING    ?=$(NAME)
KMS_KEY     ?=$(NAME)-signer
KMS_VERSION ?=1

# derived variables 
KEY_PATH    ?=$(KMS_RING)/cryptoKeys/$(KMS_KEY)/cryptoKeyVersions/$(KMS_VERSION)
SIGN_KEY    ?=projects/$(PROJECT_ID)/locations/$(REGION)/keyRings/$(KEY_PATH)
CO_KEY      ?=gcpkms://$(SIGN_KEY)
IMAGE_REG   ?=$(REG_URI)/$(PROJECT_ID)/$(REG_PATH)
IMAGE_URI   ?=$(IMAGE_REG):$(VERSION)
TEST_URI    ?=$(REG_URI)/$(PROJECT_ID)/$(REG_PATH)-test:$(VERSION)-$(shell date +%s)

all: help

version: ## Prints the current version
	@echo $(VERSION)
.PHONY: version

tag: ## Creates release tag 
	git tag -s -m "version bump to $(VERSION)" $(VERSION)
	git push origin $(VERSION)
.PHONY: tag

key: ## Build and publishes S3C tools
	@echo "Generating key-pair from: $(CO_KEY)"
	cosign generate-key-pair --kms $(CO_KEY)
.PHONY: key

builder: ## Build and publishes builder image
	@echo "\nBuild and push image"
	docker build -t $(IMAGE_URI) --platform linux/amd64 .
	docker push $(IMAGE_URI)

	docker inspect --format='{{index .RepoDigests 0}}' $(IMAGE_URI) > .image
	@$(eval IMAGE_SHA=`cat .image`)
	@echo "IMAGE_SHA: $(IMAGE_SHA)\n"
	
	@echo "Sign and verify image"
	cosign sign --key $(CO_KEY) -a version=$(VERSION) -a commit=$(COMMIT) $(IMAGE_SHA)
	cosign verify --key $(CO_KEY) $(IMAGE_SHA)

	@echo "Generate SBOM from image and attach it as attestation to the image"
	syft -o spdx-json=sbom.spdx.json $(IMAGE_SHA) | jq --compact-output > sbom.spdx.json
	cosign attest --predicate sbom.spdx.json --type spdx --key $(CO_KEY) $(IMAGE_SHA)

	@echo "Verifying all image attestations "
	cosign verify-attestation --type spdx --key $(CO_KEY) $(IMAGE_SHA) | jq '.payloadType'
.PHONY: builder

image: ## Build test image
	sed -e "s/VERSION/$(VERSION)/" example/template > example/hello
	docker build -f example/Dockerfile -t $(TEST_URI) --platform linux/amd64 .
	docker push $(TEST_URI)
	docker inspect --format='{{index .RepoDigests 0}}' $(TEST_URI) > .test
.PHONY: image

test: image ## Runs local sript 
	PROJECT=$(PROJECT_ID) \
	KEY=$(SIGN_KEY) \
	ATTESTOR=$(NAME) \
	VERSION=$(VERSION) \
	COMMIT=$(COMMIT) \
	./builder $(shell cat .test)
.PHONY: test

setup:
	gcloud services enable \
		artifactregistry.googleapis.com \
		binaryauthorization.googleapis.com \
		container.googleapis.com \
		containerregistry.googleapis.com \
		containerscanning.googleapis.com \
		containersecurity.googleapis.com

	# gcloud kms keyrings create $(KMS_RING) \
	# 	--project $(PROJECT_ID) \
	# 	--location $(REGION)

	# gcloud kms keys create $(KMS_KEY) \
	# 	--project $(PROJECT_ID) \
	# 	--location $(REGION) \
	# 	--keyring $(KMS_RING) \
	# 	--purpose asymmetric-signing \
	# 	--default-algorithm rsa-sign-pkcs1-4096-sha512

	# gcloud kms keys describe $(KMS_KEY) \
	# 	--project $(PROJECT_ID) \
	# 	--location $(REGION) \
	# 	--keyring $(KMS_RING) \
	# 	--format json | jq --raw-output '.name'

	curl "https://containeranalysis.googleapis.com/v1/projects/$(PROJECT_ID)/notes/?noteId=$(NAME)-note" \
	--request "POST" \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer $(shell gcloud auth print-access-token --project $(PROJECT_ID))" \
	--header "X-Goog-User-Project: $(PROJECT_ID)" \
	--data-binary '{"name": "projects/$(PROJECT_ID)/notes/$(NAME)-note", "attestation": {"hint": {"human_readable_name": "$(NAME) note"}}}'

	gcloud container binauthz attestors create $(NAME) \
	--project $(PROJECT_ID) \
	--attestation-authority-note-project $(PROJECT_ID) \
	--attestation-authority-note "$(NAME)-note" \
	--description "$(NAME) attestor"

	gcloud beta container binauthz attestors public-keys add \
	--project $(PROJECT_ID) \
	--attestor $(NAME) \
	--keyversion "1" \
	--keyversion-key $(KMS_KEY) \
	--keyversion-keyring $(KMS_RING) \
	--keyversion-location $(REGION) \
	--keyversion-project $(PROJECT_ID)
.PHONY: setup 


help: ## Display available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk \
		'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.PHONY: help
