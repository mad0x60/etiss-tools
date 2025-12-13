#!/bin/bash
#
# Example: Compare Decoder Performance With/Without Stats Overhead
#
# This script runs a comprehensive comparison to measure the impact of
# the stats collection overhead (steady_clock::now() calls) on decoder performance.
#

set -e

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPTS_ROOT"

echo "=========================================="
echo "Decoder Stats Overhead Comparison"
echo "=========================================="
echo ""
echo "This will compare 4 ETISS variants:"
echo "  1. profile_old_decoder          (with stats - includes timing overhead)"
echo "  2. profile_old_decoder_nostats  (no stats - pure decoder performance)"
echo "  3. profile_new_decoder          (with stats - includes timing overhead)"
echo "  4. profile_new_decoder_nostats  (no stats - pure decoder performance)"
echo ""
echo "Program: tvm_vww (runs1, runs2, runs4)"
echo "JIT: TCC"
echo ""
echo "Expected results:"
echo "  - nostats variants should be ~20% faster (no steady_clock::now() overhead)"
echo "  - This isolates the pure decoder performance difference"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Build all 4 variants if needed
echo ""
echo "Building ETISS variants (if not already built)..."
for variant in profile_old_decoder profile_old_decoder_nostats profile_new_decoder profile_new_decoder_nostats; do
    if [[ ! -f "$HOME/thesis/etiss/${variant}/bin/bare_etiss_processor" ]]; then
        echo "  Building ${variant}..."
        ./scripts/build-etiss.sh --variant ${variant}
    else
        echo "  ✓ ${variant} already built"
    fi
done

# Run the comparison
echo ""
echo "Running benchmarks..."
./tools/profiler.py \
  --profile default_runs1 default_runs2 default_runs4 \
  --etiss-variant profile_old_decoder profile_old_decoder_nostats \
                  profile_new_decoder profile_new_decoder_nostats \
  --programs tvm_vww \
  --jits TCC \
  --experiment-name decoder_stats_overhead_comparison \
  --output results/decoder_stats_overhead_comparison.json

echo ""
echo "=========================================="
echo "Comparison Complete!"
echo "=========================================="
echo ""
echo "Results saved to:"
echo "  - Summary: results/decoder_stats_overhead_comparison.json"
echo "  - Individual runs: results/jit_stats/decoder_stats_overhead_comparison/"
echo ""
echo "Quick analysis:"
echo ""
python3 -c "
import json

with open('results/decoder_stats_overhead_comparison.json') as f:
    data = json.load(f)

# Group results by profile and variant
results = {}
for r in data['results']:
    key = (r['profile'], r['etiss_variant'])
    if key not in results:
        results[key] = []
    results[key].append(r)

# Calculate averages
print('Average Wall Time (seconds):')
print('-' * 80)
print(f'{'Profile':<20} {'Old (stats)':<15} {'Old (nostats)':<15} {'New (stats)':<15} {'New (nostats)':<15}')
print('-' * 80)

for profile in ['default_runs1', 'default_runs2', 'default_runs4']:
    row = [profile]
    for variant in ['etiss_profile_old_decoder', 'etiss_profile_old_decoder_nostats', 
                    'etiss_profile_new_decoder', 'etiss_profile_new_decoder_nostats']:
        if (profile, variant) in results:
            avg_time = sum(r['wall_time'] for r in results[(profile, variant)]) / len(results[(profile, variant)])
            row.append(f'{avg_time:.4f}')
        else:
            row.append('N/A')
    print(f'{row[0]:<20} {row[1]:<15} {row[2]:<15} {row[3]:<15} {row[4]:<15}')

print()
print('Stats Overhead Analysis:')
print('-' * 80)

for profile in ['default_runs1', 'default_runs2', 'default_runs4']:
    print(f'\\n{profile}:')
    
    # Old decoder overhead
    if (profile, 'etiss_profile_old_decoder') in results and (profile, 'etiss_profile_old_decoder_nostats') in results:
        with_stats = sum(r['wall_time'] for r in results[(profile, 'etiss_profile_old_decoder')]) / len(results[(profile, 'etiss_profile_old_decoder')])
        without_stats = sum(r['wall_time'] for r in results[(profile, 'etiss_profile_old_decoder_nostats')]) / len(results[(profile, 'etiss_profile_old_decoder_nostats')])
        overhead = ((with_stats - without_stats) / without_stats) * 100
        print(f'  Old decoder stats overhead: {overhead:.1f}%')
    
    # New decoder overhead
    if (profile, 'etiss_profile_new_decoder') in results and (profile, 'etiss_profile_new_decoder_nostats') in results:
        with_stats = sum(r['wall_time'] for r in results[(profile, 'etiss_profile_new_decoder')]) / len(results[(profile, 'etiss_profile_new_decoder')])
        without_stats = sum(r['wall_time'] for r in results[(profile, 'etiss_profile_new_decoder_nostats')]) / len(results[(profile, 'etiss_profile_new_decoder_nostats')])
        overhead = ((with_stats - without_stats) / without_stats) * 100
        print(f'  New decoder stats overhead: {overhead:.1f}%')
    
    # Pure decoder comparison (without stats)
    if (profile, 'etiss_profile_old_decoder_nostats') in results and (profile, 'etiss_profile_new_decoder_nostats') in results:
        old = sum(r['wall_time'] for r in results[(profile, 'etiss_profile_old_decoder_nostats')]) / len(results[(profile, 'etiss_profile_old_decoder_nostats')])
        new = sum(r['wall_time'] for r in results[(profile, 'etiss_profile_new_decoder_nostats')]) / len(results[(profile, 'etiss_profile_new_decoder_nostats')])
        improvement = ((old - new) / old) * 100
        print(f'  Pure decoder improvement (new vs old): {improvement:.1f}%')

print()
print('Note: Positive overhead % means stats collection adds that much time')
print('      Positive improvement % means new decoder is that much faster')
"

echo ""
echo "For detailed analysis, use:"
echo "  ./tools/analyze-jit-stats.py results/jit_stats/decoder_stats_overhead_comparison/*.json"
echo ""
