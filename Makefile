CC := clang
LEX := flex
YACC := bison

override CFLAGS += -std=c23 -Wall -Wextra -Wpedantic -O3 -D_GNU_SOURCE -fPIC
override CPPFLAGS += -Iinclude -Ibuild/gen
override LDFLAGS += -flto=full -lm -ldl -lpthread -rdynamic

ifneq ($(shell command -v ccache 2>/dev/null),)
        CC := ccache $(CC)
endif

TARGET := quicksort
BUILD_DIR := build
OBJ_DIR := $(BUILD_DIR)/obj
DEP_DIR := $(BUILD_DIR)/dep
GEN_DIR := $(BUILD_DIR)/gen
JIT_DIR := $(BUILD_DIR)/jit

LEX_SRC := $(wildcard src/*.l)
YACC_SRC := $(wildcard src/*.y)

GEN_C := $(patsubst src/%.l,$(GEN_DIR)/%.lex.c,$(LEX_SRC)) \
         $(patsubst src/%.y,$(GEN_DIR)/%.tab.c,$(YACC_SRC))
GEN_H := $(patsubst src/%.l,$(GEN_DIR)/%.lex.h,$(LEX_SRC)) \
         $(patsubst src/%.y,$(GEN_DIR)/%.tab.h,$(YACC_SRC))

SRCS := $(wildcard src/*.c)
OBJS := $(patsubst src/%.c,$(OBJ_DIR)/%.o,$(SRCS)) \
        $(patsubst $(GEN_DIR)/%.c,$(OBJ_DIR)/%.o,$(GEN_C))
DEPS := $(patsubst $(OBJ_DIR)/%.o,$(DEP_DIR)/%.d,$(OBJS))

JSON_FRAGMENTS := $(patsubst $(OBJ_DIR)/%.o,$(BUILD_DIR)/%.json,$(OBJS))

.PHONY: all clean format compiledb pgo test cov coverage tui report

all: $(TARGET)

$(TARGET): $(GEN_H) $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $@ $(LDFLAGS)

$(GEN_DIR)/%.tab.c $(GEN_DIR)/%.tab.h: src/%.y | $(GEN_DIR)
	$(YACC) -d -o $(GEN_DIR)/$*.tab.c $<

$(GEN_DIR)/%.lex.c $(GEN_DIR)/%.lex.h: src/%.l $(GEN_DIR)/%.tab.h | $(GEN_DIR)
	$(LEX) --header-file=$(GEN_DIR)/$*.lex.h -o $(GEN_DIR)/$*.lex.c $<

$(OBJ_DIR)/%.o: src/%.c $(GEN_H) | $(OBJ_DIR) $(DEP_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -MF $(DEP_DIR)/$*.d -c $< -o $@

$(OBJ_DIR)/%.o: $(GEN_DIR)/%.c $(GEN_H) | $(OBJ_DIR) $(DEP_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wno-unused-function -Wno-sign-compare -Wno-unused-parameter -MMD -MP -MF $(DEP_DIR)/$*.d -c $< -o $@

$(OBJ_DIR) $(DEP_DIR) $(GEN_DIR) $(JIT_DIR) $(BUILD_DIR):
	mkdir -p $@

tui: | $(BUILD_DIR)
	cd tui && bun install && zig build -Doptimize=ReleaseFast
	cp -f tui/zig-out/lib/libqs_tui.so $(BUILD_DIR)/libqs_tui.so

test: $(GEN_H) $(GEN_C)
	zig build --build-file tests/build.zig test --summary all

cov coverage: $(GEN_H) $(GEN_C)
	zig build --build-file tests/build.zig test-exe
	rm -rf $(BUILD_DIR)/coverage
	mkdir -p $(BUILD_DIR)/coverage
	__QS_PARSER_SHUT_UP=1 __QS_UI_SHUT_UP=1 kcov \
		--include-path=$(CURDIR)/src,$(CURDIR)/include \
		--exclude-pattern=.zig,parser.y,parser.l,.tab.,.lex. \
		$(BUILD_DIR)/coverage ./tests/zig-out/bin/test_runner

compiledb: $(GEN_H) $(GEN_C) | $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/*.json
	@$(MAKE) --always-make $(JSON_FRAGMENTS)
	@sed -e '1s/^/[\n/' -e '$$s/,$$/\n]/' $(JSON_FRAGMENTS) > compile_commands.json
	@rm -f $(JSON_FRAGMENTS)

$(BUILD_DIR)/%.json: src/%.c $(GEN_H) | $(BUILD_DIR)
	$(patsubst ccache ,,$(CC)) $(CPPFLAGS) $(CFLAGS) -MJ $@ -c $< -o /dev/null

$(BUILD_DIR)/%.json: $(GEN_DIR)/%.c $(GEN_H) | $(BUILD_DIR)
	$(patsubst ccache ,,$(CC)) $(CPPFLAGS) $(CFLAGS) -MJ $@ -c $< -o /dev/null

pgo:
	$(MAKE) clean
	$(MAKE) CFLAGS="-fprofile-generate" LDFLAGS="-fprofile-generate"
	@for sim in simulations/0*.qs simulations/1*.qs; do \
		[ -f "$$sim" ] && __QS_UI_SHUT_UP=1 ./$(TARGET) --no-tui "$$sim" >/dev/null || true; \
	done
	llvm-profdata merge -output=default.profdata default.profraw
	$(MAKE) clean-KeepProf
	$(MAKE) CFLAGS="-fprofile-use=default.profdata" LDFLAGS="-fprofile-use=default.profdata"
	rm -f default.profdata default.profraw

report: $(TARGET)
	./$(TARGET) --no-tui --host-info-tex report/data/host_info.tex --host-info-csv report/data/host_info.csv
	@for sim in simulations/calibration_m.qs simulations/tp_official.qs simulations/extensions_pdq.qs simulations/jit_assembly.qs; do \
		if [ -f "$$sim" ]; then ./$(TARGET) --no-tui "$$sim"; fi; \
	done
	cd report && latexmk -pdf -interaction=nonstopmode main.tex

clean-KeepProf:
	rm -rf $(BUILD_DIR) $(TARGET)

clean: clean-KeepProf
	rm -f compile_commands.json default.profdata default.profraw

format:
	find src include -type f \( -name '*.c' -o -name '*.h' \) -exec clang-format -i {} +

-include $(DEPS)
