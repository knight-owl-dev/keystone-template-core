.PHONY: image publish all prune clean sample help

# Path to your Compose file and environment file
COMPOSE_FILE = .docker/docker-compose.yaml

# Base Docker Compose command
DC = docker compose --file $(COMPOSE_FILE) --env-file .env

# Base publish command
PUBLISH = $(DC) run --rm keystone ./.pandoc/publish.sh

# Defaults
target ?= book
format ?= pdf

# Build the Docker image
image:
	$(DC) build
	@echo ""

# Cleanup unused Docker images
prune:
	docker image prune -f
	@echo ""

# Publish a specific output (PDF or EPUB) for a given target (default: book)
# Usage: make publish [target=book] [format=pdf|epub]
publish: image
	$(PUBLISH) $(target) $(format)

# Build all supported formats for the default target
all: image
	$(PUBLISH) book pdf
	$(PUBLISH) book epub
	$(MAKE) --no-print-directory prune

# Clean up build artifacts and unused Docker images
clean: prune
	@echo "Removing generated artifacts..."
	rm -fv $(shell find ./artifacts -type f ! -name '.gitkeep' ! -name '.DS_Store')
	@echo ""

# Reset to a clean state (tracked + untracked)
reset:
	@echo "🧹 Resetting to a clean state (tracked + untracked)..."
	git reset --hard
	git clean -fd
	@echo "✅ Done. All changes and untracked content removed."
	@echo ""

# Install sample content
sample:
	@if grep -Ev '^\s*#|^\s*$$' publish.txt | grep -q .; then \
		echo "❌ Cannot install sample content: publish.txt is not empty."; \
		echo "   Please clear it manually or move your content before running 'make sample'."; \
		exit 1; \
	fi
	@echo "📦 Installing Keystone sample content..."
	cp -rv .keystone/sample/. ./
	@echo "✅ Sample content installed. You can now run 'make all' to build your first book."
	@echo ""

# Show help message
help:
	@echo ""
	@echo "Keystone Build Commands:"
	@echo "  make publish [target=book] [format=pdf|epub]   Build a specific format (default: book.pdf)"
	@echo "  make image                                     Build the Docker image"
	@echo "  make all                                       Build book.pdf and book.epub"
	@echo "  make prune                                     Prune dangling Docker images"
	@echo "  make clean                                     Prune images and delete generated artifacts"
	@echo "  make reset                                     Reset to a clean state (git reset --hard, git clean -fd)"
	@echo "  make sample                                    Install sample content (chapters and appendix)"
	@echo "  make help                                      Show this message"
	@echo ""
