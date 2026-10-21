
##

TARGET=nasmon
HOSTNAME:=$(shell hostname)
CFG_SRC:=$(if $(wildcard $(TARGET).$(HOSTNAME).cfg),$(TARGET).$(HOSTNAME).cfg,$(TARGET).cfg)

##

all: check

check: $(TARGET)
	node --check $(TARGET)
	@echo "syntax OK"
format:
	prettier --write $(TARGET)
# checks the NAS and prints the message, without publishing it
test: $(TARGET)
	./$(TARGET) $(CFG_SRC) --dry-run

.PHONY: all check format test

##

INSTALL=nasmon
DIR_INSTALL=/usr/local/bin
DIR_DEFAULT=/etc/default
DIR_SYSTEMD=/etc/systemd/system
define install_timer_systemd
	-systemctl stop $(2).timer 2>/dev/null || true
	-systemctl disable $(2).timer 2>/dev/null || true
	install -m 644 $(1).service $(DIR_SYSTEMD)/$(2).service
	install -m 644 $(1).timer $(DIR_SYSTEMD)/$(2).timer
	systemctl daemon-reload
	systemctl enable $(2).timer
	systemctl start $(2).timer || echo "Warning: Failed to start $(2).timer"
endef
install_target: $(TARGET)
	install -m 755 $(TARGET) $(DIR_INSTALL)/$(INSTALL)
# 600: it holds the NAS password
install_default: $(CFG_SRC)
	@echo "installing config from $(CFG_SRC)"
	install -m 600 $(CFG_SRC) $(DIR_DEFAULT)/$(INSTALL)
install_timer: $(TARGET).service $(TARGET).timer
	$(call install_timer_systemd,$(TARGET),$(INSTALL))
install: check install_target install_default install_timer
# a check now, instead of waiting for the timer
run:
	systemctl start $(INSTALL)
status:
	@systemctl --no-pager --lines=0 status $(INSTALL).timer $(INSTALL) || true
	@journalctl -u $(INSTALL) -n 10 --no-pager -o cat
.PHONY: install install_target install_default install_timer
.PHONY: run status

##
