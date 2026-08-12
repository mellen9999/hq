PREFIX ?= $(HOME)/.local

install:
	install -Dm755 -t $(PREFIX)/bin bin/hq bin/hq-poll bin/hq-status

uninstall:
	rm -f $(PREFIX)/bin/hq $(PREFIX)/bin/hq-poll $(PREFIX)/bin/hq-status

.PHONY: install uninstall
