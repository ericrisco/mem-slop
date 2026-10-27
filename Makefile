.PHONY: build test app run install uninstall clean release icon verify demo

PREFIX ?= /Applications

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	-pkill -x MemSlop
	open dist/MemSlop.app

install: app
	-pkill -x MemSlop
	rm -rf "$(PREFIX)/MemSlop.app"
	cp -R dist/MemSlop.app "$(PREFIX)/MemSlop.app"
	open "$(PREFIX)/MemSlop.app"

uninstall:
	-pkill -x MemSlop
	rm -rf "$(PREFIX)/MemSlop.app"

release:
	./scripts/build-app.sh --universal
	./scripts/package.sh

clean:
	rm -rf .build dist

icon:
	./scripts/make-icon.sh

verify:
	./scripts/verify.sh

demo: app
	-pkill -x MemSlop
	open dist/MemSlop.app --args --demo --open=dashboard
