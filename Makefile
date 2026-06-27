.DEFAULT_GOAL := help

.PHONY: image import publish all clean help

# Load environment variables (only for Makefile)
include project.conf

# Export host UID/GID so the container writes artifacts as the current user
export DOCKER_UID := $(shell id -u)
export DOCKER_GID := $(shell id -g)

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
PUBLISH = $(DC) run --rm $(if $(using),-e KEYSTONE_USING=$(using)) keystone ./.pandoc/publish.sh

# Defaults
format ?= pdf

# Build the Docker image
image:
	@echo "Building Docker image..." \
		&& $(DC) build

# Import a document (DOCX, ODT, RTF, HTML, etc.) from the `./artifacts` folder
# Usage: make import artifact=chapter1.docx
import: image
	@if [ -z "$(artifact)" ]; then \
		echo "ERROR: Please provide an artifact filename from the artifacts folder, e.g., make import artifact=chapter1.docx" >&2; \
		exit 1; \
	fi
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

# Publish a specific output (PDF or EPUB)
# Usage: make publish [format=pdf|epub] [using=<config>]
publish: image
	@$(PUBLISH) $(format)

# Build all supported formats
all: image
	@$(PUBLISH) pdf
	@$(PUBLISH) epub
	@$(PUBLISH) docx

# Clean up build artifacts
clean:
	@echo "Removing generated artifacts..." \
		&& rm -rf ./artifacts

# Show help message
help:
	@echo ""
	@echo "Keystone Build Commands:"
	@echo "  make publish [format=pdf|epub|docx] [using=<config>]   Build a specific format (default: pdf)"
	@echo "  make import artifact=input-file.ext                Import a document (DOCX, ODT, RTF) from ./artifacts"
	@echo "  make image                                         Build the Docker image"
	@echo "  make all                                           Build all supported formats (PDF, EPUB, DOCX)"
	@echo "  make clean                                         Delete generated artifacts from ./artifacts"
	@echo "  make help                                          Show this message"
	@echo ""
