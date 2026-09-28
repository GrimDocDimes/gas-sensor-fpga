#!/bin/bash
# =============================================================================
# run_sims.sh — Compile and run all gas sensor RTL testbenches
# Simulator  : Icarus Verilog (iverilog + vvp)
# Usage      : bash run_sims.sh         # run all
# =============================================================================
set -e

RTL_DIR="../rtl"
SIM_DIR="."
OUT_DIR="./build"

mkdir -p "$OUT_DIR"

# Colour codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass=0; fail=0

run_tb () {
    local tb_name=$1
    shift
    local sources="$@"

    echo -e "${YELLOW}━━━ Compiling $tb_name ━━━${NC}"

    if iverilog -g2005 -Wall \
        -o "$OUT_DIR/${tb_name}.vvp" \
        "$SIM_DIR/${tb_name}.v" \
        $sources 2>&1; then

        echo -e "${YELLOW}━━━ Running $tb_name ━━━${NC}"
        if vvp "$OUT_DIR/${tb_name}.vvp" 2>&1 | tee "$OUT_DIR/${tb_name}.log" | \
           grep -q "ALL TESTS PASSED"; then
            echo -e "${GREEN}✓ $tb_name PASSED${NC}"
            ((pass++)) || true
        else
            echo -e "${RED}✗ $tb_name FAILED (check $OUT_DIR/${tb_name}.log)${NC}"
            ((fail++)) || true
        fi
    else
        echo -e "${RED}✗ $tb_name COMPILE ERROR${NC}"
        ((fail++)) || true
    fi
    echo ""
}

# ── All testbenches ──────────────────────────────────────────────────────────

run_tb tb_resistance_calc \
    "$RTL_DIR/resistance_calc.v" \
    "$RTL_DIR/div_pipe.v"

run_tb tb_alarm_controller \
    "$RTL_DIR/alarm_controller.v"

run_tb tb_baseline_tracker \
    "$RTL_DIR/baseline_tracker.v"

run_tb tb_roc_detector \
    "$RTL_DIR/roc_detector.v"

run_tb tb_cross_channel_fault \
    "$RTL_DIR/cross_channel_fault.v" \
    "$RTL_DIR/div_pipe.v"

run_tb tb_axi_lite_regs \
    "$RTL_DIR/axi_lite_regs.v"

# ── Summary ───────────────────────────────────────────────────────────────────
echo "══════════════════════════════════════"
echo "  Simulation Summary"
echo "  PASS: $pass   FAIL: $fail"
if [ "$fail" -eq 0 ]; then
    echo -e "  ${GREEN}ALL TESTBENCHES PASSED${NC}"
else
    echo -e "  ${RED}*** FAILURES DETECTED — see build/*.log ***${NC}"
    exit 1
fi
echo "══════════════════════════════════════"
