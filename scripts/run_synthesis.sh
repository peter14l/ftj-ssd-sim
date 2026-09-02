#!/usr/bin/env bash
# ================================================================
# run_synthesis.sh — FTJ SSD Controller IP Block
# RTL Synthesis & PPA Dashboard Generator for Linux / macOS / WSL
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/scripts/output"
REPORT="$OUTPUT_DIR/synthesis_report.log"
NETLIST="$OUTPUT_DIR/ftj_top_controller_netlist.v"
YS_SCRIPT="$REPO_ROOT/scripts/synthesize.ys"
YOSYS_BIN="${1:-yosys}"

SEP="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}${SEP}${NC}"
echo -e "${CYAN}  FTJ SSD Controller IP — Yosys RTL Synthesis Pipeline${NC}"
echo -e "${CYAN}  Environment : Linux / macOS / WSL${NC}"
echo -e "${CYAN}  Cell Library: scripts/generic_cells.lib (130nm-class)${NC}"
echo -e "${CYAN}  Target      : 100 MHz | AXI4 Burst | 3D NAND + WL${NC}"
echo -e "${CYAN}${SEP}${NC}"

# Check for Yosys binary
if ! command -v "$YOSYS_BIN" &> /dev/null; then
    echo ""
    echo -e "${RED}  [ERROR] Yosys not found in PATH (searched: '$YOSYS_BIN')${NC}"
    echo -e "${YELLOW}  Please install Yosys:${NC}"
    echo -e "${YELLOW}    Ubuntu/Debian : sudo apt-get install yosys${NC}"
    echo -e "${YELLOW}    macOS (Homebrew): brew install yosys${NC}"
    echo -e "${YELLOW}    OSS CAD Suite : https://github.com/YosysHQ/oss-cad-suite-build/releases${NC}"
    echo -e "${YELLOW}  Or pass binary path explicitly: ./scripts/run_synthesis.sh /path/to/yosys${NC}"
    exit 1
fi

YOSYS_VER=$("$YOSYS_BIN" --version 2>&1 | head -n 1)
echo -e "${GREEN}  Yosys Found : ${YOSYS_VER}${NC}"

# Verify required files
REQUIRED_FILES=(
    "$REPO_ROOT/hdl/ftj_top_controller.v"
    "$REPO_ROOT/hdl/ftj_submission_queue.v"
    "$REPO_ROOT/hdl/nand_flash_model.v"
    "$REPO_ROOT/scripts/generic_cells.lib"
    "$YS_SCRIPT"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo -e "${RED}  [ERROR] Required file not found: $f${NC}"
        exit 1
    fi
done

# Prepare output dir
mkdir -p "$OUTPUT_DIR"

echo ""
echo -e "${YELLOW}  Running Yosys synthesis...${NC}"
echo -e "${GRAY}  Script : scripts/synthesize.ys${NC}"
echo -e "${GRAY}  Log    : scripts/output/synthesis_report.log${NC}"
echo ""

START_TIME=$(date +%s)

cd "$REPO_ROOT"
if ! "$YOSYS_BIN" -l "$REPORT" "$YS_SCRIPT"; then
    echo ""
    echo -e "${RED}  [SYNTHESIS FAILED] Yosys returned non-zero exit code.${NC}"
    echo -e "${YELLOW}  Check log: $REPORT${NC}"
    exit 1
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Parse results from report
GATE_COUNT=$(grep -m 1 "Number of cells:" "$REPORT" 2>/dev/null | awk '{print $NF}' || echo "N/A")
WIRE_COUNT=$(grep -m 1 "Number of wires:" "$REPORT" 2>/dev/null | awk '{print $NF}' || echo "N/A")
AREA_UM2=$(grep -m 1 "Chip area for" "$REPORT" 2>/dev/null | awk '{print $NF}' || echo "0")

if [ -n "$AREA_UM2" ] && [ "$AREA_UM2" != "0" ]; then
    AREA_MM2=$(awk -v a="$AREA_UM2" 'BEGIN { printf "%.6f", a / 1000000 }')
else
    AREA_UM2="N/A"
    AREA_MM2="N/A"
fi

FMAX_STR="N/A (check log)"
if grep -q "Delay.*=" "$REPORT" 2>/dev/null; then
    DELAY_NS=$(grep -m 1 "Delay.*=" "$REPORT" | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
    if [ -n "$DELAY_NS" ]; then
        FMAX_MHZ=$(awk -v d="$DELAY_NS" 'BEGIN { printf "%.1f", 1000.0 / d }')
        FMAX_STR="${FMAX_MHZ} MHz (critical path = ${DELAY_NS}ns)"
    fi
fi

# Print PPA Dashboard
echo ""
echo -e "${GREEN}${SEP}${NC}"
echo -e "${GREEN}  ╔══════════════ PPA SUMMARY DASHBOARD ══════════════╗${NC}"
echo -e "${GREEN}${SEP}${NC}"
printf "  %-35s : %s\n" "Total Gate Count (Equiv.)" "${GATE_COUNT:-N/A}"
printf "  %-35s : %s\n" "Wire Count" "${WIRE_COUNT:-N/A}"
printf "  %-35s : %s µm²\n" "Physical Area (generic_cells.lib)" "${AREA_UM2:-N/A}"
printf "  %-35s ≈ %s mm²\n" "Physical Area" "${AREA_MM2:-N/A}"
printf "  %-35s : %s\n" "Est. Fmax (ABC timing)" "${FMAX_STR}"
printf "  %-35s : %s\n" "Target Clock" "100 MHz (10 ns period)"
printf "  %-35s : %s\n" "Process Node" "Generic 130nm-class"
printf "  %-35s : %s\n" "Cell Library" "scripts/generic_cells.lib"
echo -e "${GREEN}${SEP}${NC}"
echo -e "${GRAY}  Synthesis completed in ${ELAPSED}s${NC}"
echo -e "${GRAY}  Gate-level netlist : $NETLIST${NC}"
echo -e "${GRAY}  Full synthesis log : $REPORT${NC}"
echo -e "${GREEN}${SEP}${NC}"
echo ""
