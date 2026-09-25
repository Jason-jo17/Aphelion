# Aphelion — the commands you actually need.
#
#   make setup        fetch the test framework
#   make run          play it
#   make test         the GUT suite
#   make check        everything CI checks, in CI's order
#
# GODOT can point at any 4.7.x binary:  make test GODOT=~/bin/godot
GODOT ?= godot

# bash, not /bin/sh: the test target needs `set -o pipefail` to notice that
# Godot failed when its output is being piped through tee, and dash has no
# pipefail.
SHELL := /bin/bash
GUT := -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gprefix=test_ -gsuffix=.gd -gexit -glog=1

.DEFAULT_GOAL := help
.PHONY: help setup run test refsim check format lint screenshots determinism clean

help:
	@echo 'Aphelion'
	@echo
	@echo '  make setup         fetch GUT into addons/ (once, not vendored)'
	@echo '  make run           launch the game'
	@echo '  make test          the full GUT suite (~10 min, it flies every mission)'
	@echo '  make refsim        the Python reference checks (seconds, no dependencies)'
	@echo '  make check         refsim + fixtures + format + lint + tests, as CI runs them'
	@echo
	@echo '  make format        gdformat the tree in place'
	@echo '  make lint          gdformat --check and gdlint'
	@echo '  make screenshots   regenerate the README images (needs a display or xvfb)'
	@echo '                     AUDIT=1 also writes every theme, palette and scale'
	@echo '                     to the user directory, for looking at while changing the UI'
	@echo '  make determinism   fly all fifteen reference solutions, write a report'
	@echo '  make clean         remove the import cache and generated reports'
	@echo
	@echo 'Set GODOT= if `godot` is not on your PATH.'

setup:
	./tools/fetch_gut.sh

run:
	$(GODOT) --path .

# The Python reference has no dependencies and catches most physics mistakes in
# seconds, which is why it goes first here and first in CI.
refsim:
	python3 tools/refsim/validate_physics.py
	python3 tools/refsim/ships.py
	python3 tools/refsim/author_missions.py

test:
	@test -f addons/gut/gut_cmdln.gd || { echo 'GUT is missing — run: make setup'; exit 1; }
	@# GUT reports a test script that fails to *parse* as a warning and still
	@# exits zero, which once hid two entire files. Fail on it, and check the
	@# collected count against what is on disk.
	set -o pipefail; $(GODOT) --headless $(GUT) 2>&1 | tee gut.log
	@if grep -qE 'Ignoring script|Failed to load script' gut.log; then \
		echo; echo 'GUT skipped a test script:'; \
		grep -E 'Ignoring script|Failed to load script' gut.log; exit 1; fi
	@on_disk=$$(find tests -name 'test_*.gd' | wc -l); \
	 ran=$$(grep -oE '^Scripts +[0-9]+' gut.log | grep -oE '[0-9]+'); \
	 test "$$on_disk" = "$$ran" || { echo "$$on_disk test scripts on disk, GUT ran $$ran"; exit 1; }
	@echo 'All test scripts ran.'

format:
	gdformat $$(git ls-files '*.gd')

lint:
	gdformat --check $$(git ls-files '*.gd')
	gdlint $$(git ls-files '*.gd')

# Missions first: one of the fixtures is a scan of missions/, so generating the
# fixtures against stale missions reports the staleness a round late.
fixtures:
	python3 tools/refsim/author_missions.py --write
	python3 tools/refsim/generate_fixtures.py
	@git diff --quiet -- missions tests/fixtures \
		|| { echo 'missions/ or tests/fixtures/ were stale; the regenerated files are in your working tree'; exit 1; }

check: refsim fixtures lint test
	@echo 'Everything CI checks passed.'

# Godot cannot render headless, so this needs a display. xvfb-run supplies a
# virtual one; on a desktop, drop the xvfb-run prefix.
screenshots:
	@# AUDIT=1 also writes every theme/palette/scale combination to user://audit/
	AUDIT="$(AUDIT)" xvfb-run -a -s "-screen 0 1600x900x24" \
		$(GODOT) --path . --rendering-driver opengl3 res://tools/capture_screens.tscn

determinism:
	$(GODOT) --headless --script res://tools/determinism_check.gd \
		-- --json "$(CURDIR)/determinism-$$(uname -s | tr 'A-Z' 'a-z').json"

clean:
	rm -rf .godot gut.log gut-results.xml determinism-*.json determinism-*.txt
