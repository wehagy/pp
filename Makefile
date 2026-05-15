# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Wesley Gimenes <wehagy@proton.me>

OUTDIR := $(or $(outdir),$(CURDIR)/output)
SPEC_FILE := $(wildcard $(CURDIR)/*.spec)
PKG_NAME := $(basename $(notdir $(SPEC_FILE)))
RUNNER := $(or $(filter mock,$(HOSTNAME)),$(GITHUB_ACTIONS))

DNF_CMD := \
	dnf install \
	--assumeyes \
	--nodocs \
	--setopt=install_weak_deps=False

ifeq ($(HOSTNAME),mock)
  SRPM_DIR := $(OUTDIR)
  SRPM_DEPS := \
	rpmautospec \
	rpmdevtools
else
  REVIEW_DIR := $(OUTDIR)/review
  RPM_DIR := $(OUTDIR)/rpm
  SRPM_DIR := $(OUTDIR)/srpm
  SRPM_DEPS := \
	mock \
	mock-rpmautospec \
	rpmdevtools \
	podman
endif

FEDORA_VERSION := fedora-$(shell rpm --eval "%{fedora}")
FEDORA_ARCH := $(shell rpm --eval "%{_arch}")
MOCK_BUILD_ROOT := $(FEDORA_VERSION)-$(FEDORA_ARCH)

REPO := $(shell grep -oP '^%global\s+forgeurl\s+https://github.com/\K.*' $(SPEC_FILE))
REPO_NAME := $(notdir $(REPO))

LOCAL_TAG := $(shell grep -oP '^%global\s+tag\s+\K.*' $(SPEC_FILE))
LOCAL_TAG_STRIP := $(subst v,,$(LOCAL_TAG))

REMOTE_TAG := $(notdir $(word 2,$(shell git ls-remote --refs --tags --sort='-version:refname' https://github.com/$(REPO).git)))
REMOTE_TAG_STRIP := $(subst v,,$(REMOTE_TAG))

ARCHIVE_FILE := $(REPO_NAME)-$(REMOTE_TAG_STRIP).tar.gz
HASH_FILE := $(CURDIR)/CHECKSUM

define compare_release
$(shell \
	printf '%s\n%s' "$(1)" "$(2)" | sort -VC || printf "outdated"
)
endef

update-release:
ifeq ($(call compare_release,$(REMOTE_TAG),$(LOCAL_TAG)),outdated)
	echo "[INFO] Updating from $(LOCAL_TAG) to $(REMOTE_TAG)"
	curl -fsSL https://github.com/$(REPO)/archive/$(REMOTE_TAG)/$(ARCHIVE_FILE) \
		| sha256sum \
		| sed 's/-/$(ARCHIVE_FILE)/' > $(HASH_FILE)
	sed -Ei 's/^(%global\s+tag\s+).*/\1$(REMOTE_TAG)/' $(SPEC_FILE)
	git add $(SPEC_FILE) $(HASH_FILE)
	git commit -s \
		-m "update to $(REMOTE_TAG_STRIP)" \
		-m "- upstream changelog: https://github.com/$(REPO)/releases/tag/$(REMOTE_TAG)"
else
	echo "[INFO]: No update needed"
endif

deps-srpm:
	$(DNF_CMD) $(SRPM_DEPS)

deps-rpm:
	$(DNF_CMD) \
		mock \
		podman

deps-review:
	$(DNF_CMD) \
		fedora-review

deps-all: deps-srpm deps-rpm deps-review

ifdef RUNNER
srpm: deps-srpm
endif
srpm:
	spectool --get-files $(SPEC_FILE)
	sha256sum --check $(HASH_FILE)
ifeq ($(HOSTNAME),mock)
	rpmautospec process-distgit $(SPEC_FILE) $(SPEC_FILE)
	rpmbuild -bs --nodeps \
		--define "_sourcedir $(CURDIR)" \
		--define "_srcrpmdir $(SRPM_DIR)" \
		$(SPEC_FILE)
else
	mock \
		--root $(MOCK_BUILD_ROOT) \
		--enable-plugin rpmautospec \
		--buildsrpm \
		--spec $(SPEC_FILE) \
		--sources $(CURDIR) \
		--resultdir $(SRPM_DIR)
endif

ifdef RUNNER
rpm: deps-rpm
endif
rpm:
	mock \
		--root $(MOCK_BUILD_ROOT) \
		--enable-plugin expand_spec \
		--rebuild $(SRPM_DIR)/*.src.rpm \
		--resultdir $(RPM_DIR)

ifdef RUNNER
review: deps-review
endif
review:
	rm --recursive --force $(RPM_DIR)/$(PKG_NAME)
	cd $(RPM_DIR) \
		&& fedora-review \
			--mock-config $(MOCK_BUILD_ROOT) \
			--prebuilt --rpm-spec --name *.src.rpm
	mv $(RPM_DIR)/$(PKG_NAME) $(REVIEW_DIR)
	rm --recursive --force $(REVIEW_DIR)/{BUILD,srpm,srpm-unpacked,upstream}

