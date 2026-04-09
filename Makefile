.PHONY: all test clean install debug

all:
	zig build -Doptimize=ReleaseSmall

debug:
	zig build -Doptimize=Debug

test: all
	bash tests/run.sh

install: all
	cp zig-out/bin/zigparse /usr/local/bin/

clean:
	rm -rf zig-out zig-cache
