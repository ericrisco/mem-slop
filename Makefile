.PHONY: build test app run install uninstall clean release

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
	cd dist && ditto -c -k --keepParent MemSlop.app MemSlop-$$(tr -d '[:space:]' < ../VERSION).zip
	cd dist && shasum -a 256 MemSlop-*.zip > checksums.txt

clean:
	rm -rf .build dist
