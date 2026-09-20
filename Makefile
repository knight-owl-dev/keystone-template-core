.DEFAULT_GOAL := help

.PHONY: image refresh-texlive-key import publish all clean ps down reset help

# Load environment variables (only for Makefile)
include project.conf

# Export host UID/GID so the container writes artifacts as the current user
export DOCKER_UID := $(shell id -u)
export DOCKER_GID := $(shell id -g)

# `artifacts/` is a bind-mount source, so it has to exist before a container
# starts: Docker creates a missing one as root, and on Linux the build cannot
# write there. `clean` empties it rather than removing it, against a different
# hazard — recreate the directory on the host and Docker serves the container
# the one it cached, which lists fine and fails every write.
ENSURE_ARTIFACTS = mkdir -p ./artifacts

# Path to your Compose file and environment file
COMPOSE_FILE = .docker/docker-compose.yaml

# Base Docker Compose command
DC = docker compose -p $(KEYSTONE_DOCKER_COMPOSE_PROJECT) --file $(COMPOSE_FILE) --env-file project.conf

# Base import command
IMPORT = $(DC) run --rm keystone ./.pandoc/import.sh

# Base publish command
#
# `using=<name>` selects a build configuration (a named symbol set declared in
# project.conf as KEYSTONE_DEFINE_<name>) for conditional inclusion. It is
# forwarded as an env override so it wins over the project.conf default, and it
# also suffixes the output filename so editions don't clobber each other.
#
# `strict=true|false` and `progress=off|plain|auto|verbose` override
# KEYSTONE_WARNINGS_AS_ERRORS and KEYSTONE_PROGRESS the same way, so CI can run
# `make publish strict=true` and a stuck build can be re-run with
# `progress=verbose`, neither needing an edit to project.conf.
#
# All three win over project.conf because `docker compose run -e` outranks the
# service's env_file, which is where project.conf reaches the container.
PUBLISH = $(DC) run --rm \
    $(if $(using),-e KEYSTONE_USING=$(using)) \
    $(if $(strict),-e KEYSTONE_WARNINGS_AS_ERRORS=$(strict)) \
    $(if $(progress),-e KEYSTONE_PROGRESS=$(progress)) \
    keystone ./.pandoc/publish.sh

# Defaults
format ?= pdf

# Whether a finished build stops the project's containers. `down=` on the command
# line wins over KEYSTONE_HOOKS_KEEP_ALIVE in project.conf; unset, neither stops.
#
# Boolean predicates, so a recipe asks a question rather than spelling out the
# accepted words. `$(KS_BOOL)` defines them; then `ks_true "$(flag)"` and
# `ks_false "$(flag)"` answer by exit status.
#
# The vocabulary is the one every Keystone boolean takes — true/1/yes/on and
# false/0/no/off, any case — and quotes are stripped because project.conf is read
# by both make and compose's --env-file, which disagree about them. A value that
# is neither is neither: both predicates say no, and the caller decides what an
# unrecognized setting means. tr does its own octal escapes, so \047 and \042
# name the quote characters without fighting make about quoting.
KS_BOOL = \
	ks_norm() { printf '%s' "$$1" | tr -d '\047\042' | tr '[:upper:]' '[:lower:]'; }; \
	ks_true() { case "$$(ks_norm "$$1")" in true | 1 | yes | on) return 0 ;; *) return 1 ;; esac; }; \
	ks_false() { case "$$(ks_norm "$$1")" in false | 0 | no | off) return 0 ;; *) return 1 ;; esac; }

# `down=` answers on its own when it is set to anything — including a value the
# predicates do not recognize, which is a no rather than a fall-through to
# project.conf. Unset, the project's own setting decides.
STOP_REQUESTED = \
	$(KS_BOOL); \
	if ks_true '$(down)'; then exit 0; fi; \
	if [ -n '$(down)' ]; then exit 1; fi; \
	ks_false '$(KEYSTONE_HOOKS_KEEP_ALIVE)'

# Named once so `publish` and `all` agree, and so stopping means whatever the
# `down` target means. Both run it on the way out whether the build succeeded or
# not — a failed build is the one an author repeats, and leaving a container
# behind each time is what the setting was turned on to avoid.
STOP_AFTER_BUILD = if ( $(STOP_REQUESTED) ); then $(MAKE) --no-print-directory down; fi

# Build the Docker image
image:
	@echo "Building Docker image..." \
		&& $(DC) build

# Re-vendor the TeX Live signing key when `make image` fails to verify install-tl
# because the upstream key rotated. Re-fetches it by its pinned fingerprint and
# rewrites .docker/texlive-pubkey.asc; commit the result.
refresh-texlive-key:
	@./.docker/refresh-texlive-key.sh

# Import a document (DOCX, ODT, RTF, HTML, etc.) from the `./artifacts` folder
# Usage: make import artifact=chapter1.docx
import: image
	@if [ -z "$(artifact)" ]; then \
		echo "ERROR: please provide an artifact filename from the artifacts folder, e.g., make import artifact=chapter1.docx" >&2; \
		exit 1; \
	fi
	@$(ENSURE_ARTIFACTS)
	@$(IMPORT) "$(artifact)"
	@echo ""
	@echo "Next steps:"
	@echo "  • Review your ./artifacts folder and move imported content to:"
	@echo "    → ./manuscript — to store chapters and appendices"
	@echo "    → ./assets     — to store images and other assets"
	@echo ""
	@echo "Tip: Keeping one file per chapter or section is ideal for clarity and maintainability"
	@echo ""
	@echo "Edit your Markdown files:"
	@echo "  • Adjust headings and subheadings as needed"
	@echo "  • Update to keep one file per chapter or section"
	@echo "  • Update image paths to use ./assets where applicable"
	@echo ""
	@echo "Finally, update publish.txt to include the new files in the desired order"
	@echo ""

# Publish a specific output (PDF, EPUB, DOCX or ODT)
# Usage: make publish [format=pdf|epub|docx|odt] [using=<config>] [strict=true|false]
#                     [progress=off|plain|auto|verbose] [down=true|false]
publish: image
	@$(ENSURE_ARTIFACTS)
	@status=0; $(PUBLISH) $(format) || status=$$?; \
	$(STOP_AFTER_BUILD); \
	exit $$status

# Build PDF, EPUB, and DOCX
all: image
	@$(ENSURE_ARTIFACTS)
	@status=0; { $(PUBLISH) pdf && $(PUBLISH) epub && $(PUBLISH) docx; } || status=$$?; \
	$(STOP_AFTER_BUILD); \
	exit $$status

# Clean up build artifacts. See ENSURE_ARTIFACTS above for why the directory stays.
clean:
	@echo "Removing generated artifacts..."
	@if [ -d ./artifacts ]; then find ./artifacts -mindepth 1 -delete; fi

# Report this project's containers
#
# Wraps the compose file's location and the KEYSTONE_DOCKER_COMPOSE_PROJECT
# namespace, neither of which a bare `docker compose ps` has. `-a` because a
# hook killed hard leaves only a stopped container to show for it.
ps:
	@$(DC) ps -a

# Stop this project's containers
#
# The hook cache survives this, so the next build keeps what it rendered.
down:
	@echo "Stopping project containers..." \
		&& $(DC) down --remove-orphans

# Stop this project's containers and drop what they shared
#
# The hook cache goes with them, so the next build renders everything again.
reset:
	@echo "Resetting project containers and their volumes..." \
		&& $(DC) down --volumes --remove-orphans

# Show help message
help:
	@echo ""
	@echo "Keystone Build Commands"
	@echo ""
	@echo "  make publish [format=<fmt>] [using=<cfg>]  Build one format (default: pdf)"
	@echo "               [strict=<bool>] [progress=<mode>] [down=<bool>]"
	@echo "  make all                                   Build PDF, EPUB, and DOCX"
	@echo "               [same options as publish]"
	@echo "  make import artifact=<file>                Import a document into Markdown"
	@echo ""
	@echo "  make image                                 Build the runtime image"
	@echo "  make refresh-texlive-key                   Re-vendor the TeX Live signing key"
	@echo "  make clean                                 Delete generated artifacts"
	@echo "  make ps                                    Show this project's containers"
	@echo "  make down                                  Stop this project's containers"
	@echo "  make reset                                 Stop them, drop their volumes"
	@echo "  make help                                  Show this message"
	@echo ""
	@echo "  <fmt>   pdf | epub | docx | odt"
	@echo "  <cfg>   a build configuration declared in project.conf"
	@echo "  <file>  a file Pandoc can read, in ./artifacts"
	@echo ""
