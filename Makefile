# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Wesley Gimenes <wehagy@proton.me>

OUTDIR := $(or $(outdir),$(CURDIR)/output)
SPEC_FILE := $(wildcard $(CURDIR)/*.spec)

DNF_CMD := dnf install --assumeyes --nodocs --setopt=install_weak_deps=False

ifeq ($(HOSTNAME),mock)
  SRCRPM_DIR := $(OUTDIR)
  SRPM_DEPS := rpmautospec rpmdevtools
else
  SRCRPM_DIR := $(OUTDIR)/srpm
  SRPM_DEPS := mock mock-rpmautospec rpmdevtools podman
endif

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

prepare-srpm:
	$(DNF_CMD) $(SRPM_DEPS)
	spectool --get-files $(SPEC_FILE)
	sha256sum --check $(HASH_FILE)

prepare-rpm:
	$(DNF_CMD) \
		mock \
		podman

srpm: prepare-srpm
ifeq ($(HOSTNAME),mock)
	rpmautospec process-distgit $(SPEC_FILE) $(SPEC_FILE)
	rpmbuild -bs --nodeps \
		--define "_sourcedir $(CURDIR)" \
		--define "_srcrpmdir $(SRCRPM_DIR)" \
		$(SPEC_FILE)
else
	mock \
		--enable-plugin rpmautospec \
		--buildsrpm \
			--spec $(SPEC_FILE) \
			--sources $(CURDIR) \
			--resultdir $(SRCRPM_DIR)
endif

rpm: prepare-rpm
	mock \
		--rebuild $(SRCRPM_DIR)/*.src.rpm \
		--resultdir $(OUTDIR)/rpm
