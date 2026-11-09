CC := clang
LEX := flex
YACC := bison

override CFLAGS += -std=c23 -Wall -Wextra -Wpedantic -O3 -D_GNU_SOURCE -fPIC
override CPPFLAGS += -Iinclude -Ibuild/gen -DQS_SOURCE_ROOT=\"$(CURDIR)\"
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
	cd tui && bun install && zig build -Drelease
	cp -f tui/zig-out/lib/libqs_tui.so $(BUILD_DIR)/libqs_tui.so

test: $(GEN_H) $(GEN_C)
	zig build --build-file tests/build.zig test --summary all

COV_DIR := $(BUILD_DIR)/coverage
COV_SIM_DIR := $(BUILD_DIR)/cov-sim
KCOV_FLAGS := --include-path=$(CURDIR)/src,$(CURDIR)/include \
	--exclude-pattern=.zig,parser.y,parser.l,.tab.,.lex.
COV_SIMS := $(sort $(wildcard simulations/*.qs))
COV_SIM_OUT := $(patsubst simulations/%.qs,$(COV_DIR)/sim-%,$(COV_SIMS))

# Simulations run from a sandbox cwd so their output_csv files never overwrite report/data.
cov coverage: $(GEN_H) $(GEN_C)
	zig build --build-file tests/build.zig test-exe
	rm -rf $(COV_DIR)
	mkdir -p $(COV_DIR)/sandbox
	__QS_PARSER_SHUT_UP=1 __QS_UI_SHUT_UP=1 kcov $(KCOV_FLAGS) \
		$(COV_DIR)/tests ./tests/zig-out/bin/test_runner
	$(MAKE) BUILD_DIR=$(COV_SIM_DIR) TARGET=$(COV_SIM_DIR)/quicksort CFLAGS=-g
	@for sim in $(COV_SIMS); do \
		n=$$(basename $$sim .qs); \
		(cd $(COV_DIR)/sandbox && __QS_PARSER_SHUT_UP=1 __QS_UI_SHUT_UP=1 kcov $(KCOV_FLAGS) \
			$(CURDIR)/$(COV_DIR)/sim-$$n $(CURDIR)/$(COV_SIM_DIR)/quicksort --no-tui $(CURDIR)/$$sim >/dev/null) || exit 1; \
	done
	kcov --merge $(COV_DIR)/simulator $(COV_SIM_OUT)
	kcov --merge $(COV_DIR)/merged $(COV_DIR)/tests $(COV_DIR)/simulator

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
	mkdir -p $(BUILD_DIR)/pgo-sandbox
	rm -f pgo-train.log
	@for sim in simulations/0*.qs simulations/1*.qs; do \
		[ -f "$$sim" ] && (cd $(BUILD_DIR)/pgo-sandbox && LLVM_PROFILE_FILE="$(CURDIR)/pgo_%p.profraw" __QS_UI_SHUT_UP=1 $(CURDIR)/$(TARGET) --no-tui "$(CURDIR)/$$sim" >/dev/null 2>>$(CURDIR)/pgo-train.log) || true; \
	done
	@echo "PGO training stderr: pgo-train.log ($$(grep -c 'warning:' pgo-train.log || true) warnings)"
	llvm-profdata merge -output=default.profdata pgo_*.profraw
	rm -f pgo_*.profraw
	$(MAKE) clean-KeepProf
	$(MAKE) CFLAGS="-fprofile-use=default.profdata" LDFLAGS="-fprofile-use=default.profdata"
	rm -f default.profdata

REPORT_CSVS = report/data/host_info.csv \
              report/data/calibration_m.csv \
              report/data/tp_official.csv \
              report/data/extensions_pdq.csv \
              report/data/jit_assembly.csv

report/data/values.tex: $(REPORT_CSVS) report/macros.awk
	awk -f report/macros.awk $(REPORT_CSVS) > $@

report: $(TARGET) tui
	./$(TARGET) --sysinfo-tex report/data/host_info.tex --sysinfo-csv report/data/host_info.csv
	@for sim in simulations/calibration_m.qs simulations/tp_official.qs simulations/extensions_pdq.qs simulations/jit_assembly.qs; do \
		if [ -f "$$sim" ]; then ./$(TARGET) "$$sim"; fi; \
	done
	$(MAKE) report/data/values.tex
	cd report && latexmk -pdf -interaction=nonstopmode main.tex

clean-KeepProf:
	rm -rf $(BUILD_DIR) $(TARGET)

clean: clean-KeepProf
	rm -f compile_commands.json default.profdata default.profraw

format:
	find src include -type f \( -name '*.c' -o -name '*.h' \) -exec clang-format -i {} +

-include $(DEPS)
