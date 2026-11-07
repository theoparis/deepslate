V ?= v
TEST_DIR ?= vinecraft 
BUILD_DIR ?= build

.PHONY: all test tools clean
all: vinecraft tools

vinecraft: $(shell find vinecraft -type f \( -name '*.v' -o -name '*.h' \)) v.mod
	$(V) $(VFLAGS) -o $(BUILD_DIR)/bin/$@ vinecraft

tools: $(addprefix $(BUILD_DIR)/bin/,bench worldmap packcheck)

$(BUILD_DIR)/bin/%: tools/v/%/main.v $(shell find vinecraft -type f \( -name '*.v' -o -name '*.h' \))
	mkdir -p $(BUILD_DIR)/bin
	$(V) $(VFLAGS) -o $@ tools/v/$*

test:
	$(V) $(VFLAGS) test $(TEST_DIR)

clean:
	rm -rf $(BUILD_DIR)
