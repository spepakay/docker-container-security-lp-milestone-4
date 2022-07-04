default: all 

all: build lint policies bom scan sign

build:
	@echo "Building Hugo Builder container..."
	@docker build \
		--build-arg CREATE_DATE=`date -u +'%Y-%m-%dT%H:%M:%SZ'` \
		--build-arg REVISION=`git rev-parse HEAD` \
		--build-arg BUILD_VERSION=1.0.0 \
		-t lp/hugo-builder .
	@echo "Hugo Builder container built!"
	@docker images lp/hugo-builder

lint:
	@echo "Linting the Hugo Builder container..."
	@docker run --rm -i hadolint/hadolint:v1.17.5-alpine \
		hadolint --ignore DL3018 - < Dockerfile
	@echo "Linting completed!" 

#gov_policy:
#	@echo "Checking container policy..."
#	@docker run --rm -it --privileged -v $(PWD):/root/ \
#		projectatomic/dockerfile-lint \
#		dockerfile_lint -r policies/governance_rules.yml
#	@echo "Container policy checked!"

policies:
	@echo "Checking FinShare Container policies..."
	@docker run --rm -it --privileged -v $(PWD):/root/ \
		projectatomic/dockerfile-lint \
		dockerfile_lint -r policies/all_policy_rules.yml
	@echo "FinShare Container policies checked!"

#hugo_build:
#	@echo "Building the OrgDocs Hugo site..."
#	@docker run --rm -it -v $(PWD)/orgdocs:/src lp/hugo-builder hugo
#	@echo "OrgDocs Hugo site built!"

hugo_build:
	@echo "Building the OrgDocs Hugo site..."
	@docker run --rm -it \
		--mount type=bind,src=${PWD}/orgdocs,dst=/src \
		lp/hugo-builder hugo
	@echo "OrgDocs Hugo site built!"

#start_server:
#	@echo "Serving the OrgDocs Hugo site..."
#	@docker run -d --rm -it -v $(PWD)/orgdocs:/src -p 1313:1313 \
#		--name hugo_server lp/hugo-builder hugo server -w --bind=0.0.0.0 
#	@echo "OrgDocs Hugo site being served!"
#	@docker ps --filter name=hugo_server

start_server:
	@echo "Serving the OrgDocs Hugo site..."
	@docker run -d --rm -it --name hugo_server \
		--mount type=bind,src=${PWD}/orgdocs,dst=/src \
		-p 1313:1313 lp/hugo-builder hugo server -w --bind=0.0.0.0
	@echo "OrgDocs Hugo site being served!"
	@docker ps --filter name=hugo_server

start_trusted_server:
	@echo "Starting serving the trusted OrgDocs Hugo site..."
	@DOCKER_CONTENT_TRUST=1 \
	docker run -d --rm -it --name hugo_server \
		--mount type=bind,src=${PWD}/orgdocs,dst=/src \
		-p 1313:1313 cato1971/hugo-builder:1.0.0 hugo server -w --bind=0.0.0.0
	@echo "Trusted OrgDocs Hugo site being served!"
	@docker ps --filter name=hugo_server

check_health:
	@echo "Checking the health of the Hugo Server..."
	@docker inspect --format='{{json .State.Health}}' hugo_server

stop_server:
	@echo "Stopping the OrgDocs Hugo site..."
	@docker stop hugo_server
	@echo "OrgDocs Hugo site stopped!"

inspect_labels:
	@echo "Inspecting Hugo Server Container labels..."
	@echo "\nmaintainer set to..."
	@docker inspect --format '{{ index .Config.Labels "maintainer" }}' \
		hugo_server
	@echo "\ncreate date set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.create_date" }}' \
		hugo_server
	@echo "\nrevision set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
		hugo_server
	@echo "\nversion set to..."
	@docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' \
		hugo_server
	@echo "\nHugo version set to..."
	@docker inspect --format '{{ index .Config.Labels "hugo_version"}}' \
		hugo_server
	@echo "\nLabels inspected!"

scan:
	@echo "Scanning the Hugo Builder Container Image..."
	@docker run -d --rm -it --name clair-db -p 5432:5432 \
		arminc/clair-db:2020-04-18
#		arminc/clair-db:`date +%Y-%m-%d -d "yesterday"`
	@docker run -d --rm -it --name clair \
		--net=host -p 6060-6061:6060-6061 -v $(PWD)/clair_config:/config \
		quay.io/coreos/clair:v2.1.2 -config=/config/config.yaml
	@clair-scanner --ip localhost lp/hugo-builder
#	@clair-scanner --ip localhost fusionauth/fusionauth-app:latest
	@docker stop clair clair-db
	@echo "Scan of the Hugo Builder Container completed!"

bom:
	@echo "Creating Bill of Materials..."
	@docker run --rm --privileged \
		-v /var/run/docker.sock:/var/run/docker.sock \
		--mount type=bind,source=$(PWD)/workdir,target=/hostmount \
		ternd:2.0.0 report -f spdxtagvalue -i lp/hugo-builder:latest > bom.spdx
	@ls -la bom.spdx
	@echo "Bill of Materials created!"

# NOTE: Requires the DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE env variable to
#   be set and to be signed into DockerHub if using it to store images.
sign:
	@echo "Signing the container..."
	@docker tag lp/hugo-builder:latest cato1971/hugo-builder:1.0.0
	@docker trust sign cato1971/hugo-builder:1.0.0
	@echo "Signed the container!"

dct_key_info:
	@echo "local DCT key info..."
	@notary -d ~/.docker/trust key list
	@echo "hub DCT key info for hugo-builder..."
	@notary -s https://notary.docker.io -d ~/.docker/trust \
		 list docker.io/cato1971/hugo-builder

docker_clean:
	@docker image prune -f
	@docker container prune -f
	@docker volume prune -f

.PHONY: build lint gov_policies policies hugo_build \
  start_server check_health stop_server inspect_labels scan \
  docker_clean bom start_trusted_server sign dct_key_info
