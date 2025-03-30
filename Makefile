build:
	zig build -Doptimize=ReleaseFast

install: build
	sudo cp zig-out/bin/makker /usr/local/bin/makker

uninstall:
	sudo rm /usr/local/bin/makker

clean:
	rm -rf zig-out
	rm -rf .zig-cache
