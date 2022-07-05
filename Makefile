default: webserver

build: Dockerfile
	@echo "Building Hugo Builder container..."
	@docker build --build-arg REVISION=`git rev-parse HEAD` -t lp/hugo-builder .
	@echo "Hugo Builder container built!"
	@docker images lp/hugo-builder

lint: Dockerfile
	@echo "Linting Dockerfile"
	@docker run --rm -i -v ${PWD}:/src ghcr.io/hadolint/hadolint hadolint --ignore DL3018 /src/Dockerfile

policies:
	@echo "Checking FinShare Container policies..."
	@docker container run --rm -it --privileged -v $(PWD):/root projectatomic/dockerfile-lint dockerfile_lint -r policies/all_policy_rules.yml
	@echo "FinShare Container policies checked!"

website: build
	@echo "Stopping stale container..."
	- @docker container rm hugo-website -f
	@echo "Building website..."
	@docker container run --rm -it -v ${PWD}/orgdocs:/src lp/hugo-builder hugo

webserver: website
	@echo "Starting webserver..."
	@docker container run --rm -d --name hugo-website -p 1313:1313 -v ${PWD}/orgdocs:/src lp/hugo-builder hugo serve -w --bind=0.0.0.0
	@docker container ps --filter name=hugo-website

health: webserver
	@echo "Checking the health of the Hugo Server..."
	@docker container inspect --format='{{json .State.Health}}' hugo-website

scan: build
	@echo "Creating the index db..."
	@docker container run -d --rm -it --name clair-db -p 5432:5432 arminc/clair-db
	@docker container run -d --rm -it --name clair --net=host -p 6060-6061:6060-6061 -v $(PWD)/clair_config:/config quay.io/coreos/clair:v2.1.2 -config=/config/config.yaml
	@echo "Scanning hugo-builder image..."
	@docker container run -d --rm -it arminc/clair-scanner --ip localhost lp/hugo-builder
	@echo "Scanning fusionauth-app image..."
	@docker container run -d --rm -it arminc/lair-scanner --ip localhost fusionauth/fusionauth-app:latest

inspect: webserver
	@echo "Inspecting labels..."
	@docker container inspect --format '{{ index .Config.Labels "maintainer" }}' hugo-website
	@docker container inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' hugo-website
	@docker container inspect --format '{{ index .Config.Labels "org.opencontainers.image.create_date" }}' hugo-website
	@docker container inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' hugo-website
	@docker container inspect --format '{{ index .Config.Labels "hugo_version" }}' hugo-website

bom: build
	@echo "Creating bom..."
	@docker run --rm --privileged -v $(PWD)/workdir:/hostmount ternd:2.0.0 report -f spdxtagvalue -i lp/hugo-builder > bom.spdx	

keys:
	@echo "Create a repository spepakay/hugo-builder in Docker Hub. Substitute 'spepakay' with your username / namespace..."
	@echo "Login to your Docker Hub account. docker login... "
	@echo "Generating keys..."
	@docker trust key generate spepakay
	@echo "Add a signer to the DCT. Substitute 'spepakay' with your username / namespace..."
	@docker trust signer add --key spepakay.pub spepakay spepakay/hugo-builder

sign: keys
	@echo "Signing container image with key..."
	@echo "Set the DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE to the passphrase used while creating the keys"
	#TODO: @docker trust sign ....

dct:
	@echo "Show local DCT info..."
	@notary -d ~/.docker/trust/ key list
	@echo "Show remote DCT info for hugo-builder
	#TODO: @notary -s https://notary.docker.io .....

.PHONY: build lint policies website webserver health scan inspect bom dct sign keys
