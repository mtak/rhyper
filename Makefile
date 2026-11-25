# Portable across macOS /usr/bin/make (GNU Make 3.81) and BSD make:
# no .RECIPEPREFIX, no $(shell), no !=, no $< outside suffix rules.

APP        = rhyper
LABEL      = nl.mtak.rhyper
SRC        = main.swift Hyper.swift
TEST_SRC   = Hyper.swift tests/main.swift
TEST_BIN   = $(BUILD_DIR)/$(APP)-tests
BUILD_DIR  = build
BIN        = $(BUILD_DIR)/$(APP)

PREFIX     = $(HOME)/.local
BINDIR     = $(PREFIX)/bin
AGENT_DIR  = $(HOME)/Library/LaunchAgents
PLIST_IN   = $(LABEL).plist.in
PLIST      = $(AGENT_DIR)/$(LABEL).plist
LOG        = $(HOME)/Library/Logs/$(APP).log

SWIFTC     = xcrun swiftc
SWIFTFLAGS = -O -swift-version 6

.PHONY: all build test run clean install uninstall agent-install agent-uninstall load unload restart

all: build

build: $(BIN)

$(BIN): $(SRC)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFTFLAGS) -o $(BIN) $(SRC)

test: $(TEST_BIN)
	./$(TEST_BIN)

$(TEST_BIN): $(TEST_SRC)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFTFLAGS) -o $(TEST_BIN) $(TEST_SRC)

run: build
	./$(BIN)

clean:
	rm -rf $(BUILD_DIR)

# rm before cp: overwriting a signed Mach-O in place (same inode) can get the
# next launch killed with "Code Signature Invalid".
install: build
	@mkdir -p "$(BINDIR)"
	rm -f "$(BINDIR)/$(APP)"
	cp $(BIN) "$(BINDIR)/$(APP)"
	@echo "Installed $(BINDIR)/$(APP) (re-grant Accessibility if this replaced an older build)"

uninstall:
	rm -f "$(BINDIR)/$(APP)"

# --- LaunchAgent ------------------------------------------------------------

agent-install: install
	@mkdir -p "$(AGENT_DIR)" "$(HOME)/Library/Logs"
	sed -e "s|@LABEL@|$(LABEL)|g" -e "s|@BIN@|$(BINDIR)/$(APP)|g" -e "s|@LOG@|$(LOG)|g" $(PLIST_IN) > "$(PLIST)"
	plutil -lint "$(PLIST)"

agent-uninstall: unload
	rm -f "$(PLIST)"

load:
	launchctl bootstrap gui/$$(id -u) "$(PLIST)"

unload:
	-launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null

restart:
	launchctl kickstart -k gui/$$(id -u)/$(LABEL)
