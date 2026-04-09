ZIG ?= $(HOME)/bin/zig

.PHONY: all test clean install

SRC = src/main.zig
OUT = docparse

all: $(OUT)

$(OUT): $(SRC) src/pdf.zig src/table.zig src/text.zig src/detect.zig
	$(ZIG) build-exe $< -O ReleaseSmall -fstrip --name $(OUT)
	@echo "Built $(OUT) ($$(du -h $(OUT) | cut -f1))"

debug: $(SRC) src/pdf.zig src/table.zig src/text.zig src/detect.zig
	$(ZIG) build-exe $< -O Debug --name $(OUT)-debug

test: $(OUT)
	bash tests/run.sh

install: $(OUT)
	cp $(OUT) /usr/local/bin/

clean:
	rm -f $(OUT) $(OUT)-debug
