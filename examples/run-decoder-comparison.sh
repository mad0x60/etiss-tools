#!/bin/bash
#
# Example: Decoder Comparison Study
#
# This script demonstrates how to run a comprehensive decoder comparison
# using the enhanced profiler with experiment organization.
#

set -e

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPTS_ROOT"

echo "=========================================="
echo "Decoder Comparison Study"
echo "=========================================="
echo ""
echo "This will run tvm_vww benchmark with:"
echo "  - 5 different run counts (1, 2, 4, 8, 16)"
echo "  - 2 decoder variants (old vs new)"
echo "  - TCC JIT compiler"
echo ""
echo "Results will be organized in:"
echo "  results/jit_stats/decoder_comparison/"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Run the comparison
./tools/profiler.py \
  --profile default_runs1 default_runs2 default_runs4 default_runs8 default_runs16 \
  --etiss-variant profile_old_decoder profile_new_decoder \
  --programs tvm_vww \
  --jits TCC \
  --experiment-name decoder_comparison \
  --output results/decoder_comparison_results.json

echo ""
echo "=========================================="
echo "Comparison Complete!"
echo "=========================================="
echo ""
echo "Results saved to:"
echo "  - Summary: results/decoder_comparison_results.json"
echo "  - Individual runs: results/jit_stats/decoder_comparison/"
echo ""
echo "Files generated:"
ls -1 results/jit_stats/decoder_comparison/ | head -10
echo ""
echo "To analyze the results, you can:"
echo ""
echo "1. Analyze all decoder comparison results:"
echo "   ./tools/analyze-jit-stats.py results/jit_stats/decoder_comparison/*.json"
echo ""
echo "2. Compare only old decoder:"
echo "   ./tools/analyze-jit-stats.py results/jit_stats/decoder_comparison/*variant-profile_old_decoder*.json"
echo ""
echo "3. Compare only new decoder:"
echo "   ./tools/analyze-jit-stats.py results/jit_stats/decoder_comparison/*variant-profile_new_decoder*.json"
echo ""
echo "4. Compare specific run count (e.g., runs1):"
echo "   ./tools/analyze-jit-stats.py results/jit_stats/decoder_comparison/*profile-default_runs1*.json"
echo ""
