# ----------------------------------------------------------------------------
# Image source: where this image is published.
#
# These two values determine the fully-qualified image name. They live at the
# top of the Makefile because the canonical home for this image may move
# (e.g. to another org or a different artifact registry),
# and we want a single place to change it.
#
# Override on the command line if needed:
#   make build REGISTRY=ghcr.io/some-org REPOSITORY=openresty-oidc
# ----------------------------------------------------------------------------
REGISTRY    ?= us-west1-docker.pkg.dev/moz-fx-platform-artifacts/platform-shared-images
REPOSITORY  ?= openresty-oidc
IMAGE_SOURCE ?= https://github.com/mozilla/openresty-oidc

# ----------------------------------------------------------------------------
# Versions: bump these to mint a new build.
# ----------------------------------------------------------------------------
OPENRESTY_VERSION         ?= 1.29.2.5
OPENRESTY_VARIANT         ?= alpine
LUA_RESTY_OPENIDC_VERSION ?= 1.7.6
LUA_VERSION               ?= 5.1
BUILD_NUMBER              ?= 0

# ----------------------------------------------------------------------------
# Derived values: do not normally override.
# ----------------------------------------------------------------------------
IMAGE_TAG  ?= $(OPENRESTY_VERSION)-$(BUILD_NUMBER)-$(OPENRESTY_VARIANT)
IMAGE_NAME ?= $(REGISTRY)/$(REPOSITORY)
IMAGE      ?= $(IMAGE_NAME):$(IMAGE_TAG)
PLATFORM   ?= linux/amd64

BUILD_ARGS = \
	--build-arg OPENRESTY_VERSION=$(OPENRESTY_VERSION) \
	--build-arg OPENRESTY_VARIANT=$(OPENRESTY_VARIANT) \
	--build-arg LUA_RESTY_OPENIDC_VERSION=$(LUA_RESTY_OPENIDC_VERSION) \
	--build-arg LUA_VERSION=$(LUA_VERSION) \
	--build-arg IMAGE_SOURCE=$(IMAGE_SOURCE) \
	--build-arg IMAGE_VERSION=$(IMAGE_TAG)

.PHONY: help
help:
	@echo "Targets:"
	@echo "  build       Build the image (tag: $(IMAGE))"
	@echo "  smoke-test  Run smoke tests against the built image"
	@echo "  push        Push the built image to $(REGISTRY)"
	@echo "  print-tag   Print the computed image tag"
	@echo "  print-image Print the fully-qualified image name"
	@echo "  clean       Remove the locally-tagged image"

.PHONY: build
build:
	docker build \
		--platform $(PLATFORM) \
		$(BUILD_ARGS) \
		-t $(IMAGE) \
		.

.PHONY: smoke-test
smoke-test:
	@echo "==> nginx -V"
	docker run --rm --platform $(PLATFORM) \
		--entrypoint /usr/local/openresty/nginx/sbin/nginx \
		$(IMAGE) -V
	@echo
	@echo "==> runtime user"
	docker run --rm --platform $(PLATFORM) --entrypoint id $(IMAGE)
	@echo
	@echo "==> lua-resty-openidc version (grep)"
	docker run --rm --platform $(PLATFORM) --entrypoint sh $(IMAGE) -c \
		'grep -E "_VERSION" /usr/local/openresty/luajit/share/lua/$(LUA_VERSION)/resty/openidc.lua | head -1'
	@echo
	@echo "==> require resty.openidc + resty.session + cjson via resty CLI"
	docker run --rm --platform $(PLATFORM) --entrypoint /usr/local/openresty/bin/resty $(IMAGE) \
		-e 'for _, m in ipairs({"resty.openidc","resty.session","cjson"}) do local ok, v = pcall(require, m); print(m, ok, type(v)=="table" and v._VERSION or "") end'
	@echo
	@echo "==> start container, check logs, stop"
	@docker rm -f oidc-smoke >/dev/null 2>&1 || true
	docker run -d --platform $(PLATFORM) --name oidc-smoke $(IMAGE)
	@sleep 2
	@docker logs oidc-smoke
	@state=$$(docker inspect -f '{{.State.Status}}' oidc-smoke); \
	docker stop oidc-smoke >/dev/null 2>&1 || true; \
	docker rm -f oidc-smoke >/dev/null 2>&1 || true; \
	if [ "$$state" != "running" ]; then \
		echo "FAIL: container exited (state=$$state)"; exit 1; \
	fi
	@echo "smoke-test: OK"

.PHONY: push
push:
	docker push $(IMAGE)

.PHONY: print-tag
print-tag:
	@echo $(IMAGE_TAG)

.PHONY: print-image
print-image:
	@echo $(IMAGE)

.PHONY: clean
clean:
	-docker rmi $(IMAGE)
