.PHONY: venv lint lint-verbose help clean

VENV_DIR := .venv
PYTHON := $(VENV_DIR)/bin/python
PIP := $(VENV_DIR)/bin/pip
ANSIBLE_LINT := $(VENV_DIR)/bin/ansible-lint

help:
	@echo "Available targets:"
	@echo "  make venv           - Create Python virtual environment"
	@echo "  make lint           - Run ansible-lint"
	@echo "  make lint-verbose   - Run ansible-lint with verbose output"
	@echo "  make clean          - Remove virtual environment"
	@echo "  make help           - Show this help message"

venv:
	@echo "Creating virtual environment..."
	python3 -m venv $(VENV_DIR)
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt 2>/dev/null || echo "requirements.txt not found, installing ansible-lint==26.1.1 only"
	$(PIP) install ansible-lint==26.1.1
	@echo "Virtual environment created at $(VENV_DIR)"

lint: venv
	@echo "Running ansible-lint..."
	@. $(VENV_DIR)/bin/activate && ansible-lint

lint-verbose: venv
	@echo "Running ansible-lint with verbose output..."
	@. $(VENV_DIR)/bin/activate && ansible-lint -v

clean:
	@echo "Removing virtual environment..."
	rm -rf $(VENV_DIR)
	@echo "Virtual environment removed"
