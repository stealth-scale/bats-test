# The stealth test image for bats. `make help` lists the targets.
#
#   make image                                  # bash 5.2, bats 1.14.0, on Alpine
#   make image BASH_VERSION=4.4 BATS_VERSION=1.7.0
#   make image DISTRO=fedora                    # Fedora's bash and bats, glibc
#   make test                                   # the image's own tests, inside it
#   make matrix                                 # every published cell: image and test
#   make push                                   # to $(REGISTRY); log in first
SHELL := bash
.DEFAULT_GOAL := help

RUNTIME      ?= podman
REGISTRY     ?= ghcr.io/stealth-scale
BASH_VERSION ?= 5.2
BATS_VERSION ?= 1.14.0
DISTRO       ?= alpine
KCOV_VERSION ?= v43

ifeq ($(DISTRO),fedora)
CONTAINERFILE = Containerfile.fedora
TAG           = fedora
else ifeq ($(DISTRO),builder)
CONTAINERFILE = Containerfile.builder
TAG           = builder
else
CONTAINERFILE = Containerfile
TAG           = bash$(BASH_VERSION)-bats$(BATS_VERSION)
endif
IMAGE = $(REGISTRY)/bats-test:$(TAG)

# The cells `make matrix` and CI build: bash versions by bats versions, plus Fedora.
BASH_VERSIONS = 4.4 5.1 5.2 5.3
BATS_VERSIONS = 1.7.0 1.14.0

# As the calling user, no network, no capabilities; kcov's bash engine needs none.
# No --init: the entrypoint is the init and forwards signals itself.
TEST_RUN = $(RUNTIME) run --rm --network=none --cap-drop=ALL --security-opt=label=disable \
      --user $(shell id -u):$(shell id -g) $(if $(filter podman,$(RUNTIME)),--userns=keep-id) \
      --volume "$(CURDIR):/code:ro" --volume "$(CURDIR)/coverage:/code/coverage" --workdir /code

# The builder image runs a container engine, so it gets none of that. It keeps its own
# user, because rootless nesting works through the subuid range that user was given, and
# it needs /dev/fuse for the overlay its inner engine mounts. It has a network because
# the suites in it pull images. The checkout is writable: a build writes.
BUILDER_RUN = $(RUNTIME) run --rm --security-opt=label=disable --device /dev/fuse \
      --volume "$(CURDIR):/code" --workdir /code

ifeq ($(DISTRO),builder)
RUN = $(BUILDER_RUN)
else
RUN = $(TEST_RUN)
endif

.PHONY: help image test matrix push lint check clean

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{ printf "  %-8s %s\n", $$1, $$2 }'

image: ## Build $(IMAGE)
	$(RUNTIME) build -q -f $(CONTAINERFILE) \
		--build-arg BASH_VERSION=$(BASH_VERSION) --build-arg BATS_VERSION=$(BATS_VERSION) \
		--build-arg KCOV_VERSION=$(KCOV_VERSION) -t $(IMAGE) .

test: image ## Run tests/image.bats inside $(IMAGE)
	rm -rf coverage && mkdir coverage
	$(RUN) $(IMAGE) test --print-output-on-failure tests/image.bats

matrix: ## Build and test every cell
	@for bash in $(BASH_VERSIONS); do for bats in $(BATS_VERSIONS); do \
		$(MAKE) --no-print-directory test BASH_VERSION=$$bash BATS_VERSION=$$bats || exit 1; \
	done; done
	@$(MAKE) --no-print-directory test DISTRO=fedora

push: ## Push $(IMAGE); the default cell is also pushed as latest
	$(RUNTIME) push $(IMAGE)
	@if [ "$(TAG)" = "bash5.2-bats1.14.0" ]; then \
		$(RUNTIME) tag $(IMAGE) $(REGISTRY)/bats-test:latest && $(RUNTIME) push $(REGISTRY)/bats-test:latest; fi

lint: ## Run shellcheck over the scripts and the tests
	shellcheck bin/entrypoint bin/kcov-bats bin/bats-recording-status tests/image.bats tests/fixture/tests/*.bats

check: lint test ## What CI runs per cell

clean: ## Remove the coverage output of the image tests
	rm -rf coverage
