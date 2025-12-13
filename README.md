# ETISS Profiling Tools

## Quick Start

### 1. Configure Environment

Edit `config/env.conf` to set your paths:

```bash
ETISS_ROOT=/path/to/etiss
EXAMPLES_ROOT=/path/to/etiss_riscv_examples
RISCV_TOOLCHAIN_PREFIX=riscv32-unknown-elf-
```

### 2. Build ETISS and Examples

```bash
# Build ETISS with a specific variant
./scripts/build-etiss.sh --variant default

# Build example programs
./scripts/build-examples.sh --profile default --program hello_world
```

### 3. Run Benchmarks

```bash
# Basic benchmark
./tools/profiler.py \
    --programs hello_world \
    --profile default \
    --etiss-variant default \
    --jits TCC

# Multiple configurations
./tools/profiler.py \
    --programs dhrystone coremark \
    --profile default \
    --etiss-variant default \
    --jits TCC GCC LLVM \
    --block-sizes 50 100 200
```

Results are saved as JSON files in `results/jit_stats/`.

## Configuration

### ETISS Build Variants defined in (`config/etiss-builds.json`)

**Structure:**
```json
{
  "builds": {
    "variant_name": {
      "cmake_flags": "-DCMAKE_CXX_STANDARD=17 -DCMAKE_BUILD_TYPE=Release",
      "build_dir": "build",
      "description": "Description"
    }
  }
}
```

### Example Build Profiles defined in (`config/example-builds.json`)

**Structure:**
```json
{
  "builds": {
    "profile_name": {
      "arch": "rv32gc",
      "abi": "ilp32f",
      "cmake_flags": "",
      "build_dir": "build",
      "runs_count": 1,
      "description": "Description"
    }
  }
}
```

### Environment (`config/env.conf`)

Set paths and toolchain:
```bash
ETISS_ROOT=/path/to/etiss
EXAMPLES_ROOT=/path/to/etiss_riscv_examples
RISCV_TOOLCHAIN_PREFIX=riscv32-unknown-elf-
DEFAULT_ETISS_ARCH=RV32IMACFD
```

## Advanced Usage

### Multiple Profiles and Variants

Test all combinations of profiles and variants:

```bash
./tools/profiler.py \
    --profile default_runs1 default_runs2 default_runs4 \
    --etiss-variant profile default \
    --programs tvm_vww \
    --jits TCC \
    --experiment-name my_experiment \
    --output results/my_experiment.json
```

This tests 3 profiles × 2 variants = 6 benchmark runs.

### Organize by Experiment

Use `--experiment-name` to organize results:

```bash
./tools/profiler.py \
    --programs dhrystone \
    --jits TCC GCC \
    --experiment-name jit_comparison

# Results saved to:
# results/jit_stats/jit_comparison/*.json
```

## Project Structure

```
etiss-profiling-scripts/
├── config/
│   ├── env.conf              # Environment configuration
│   ├── etiss-builds.json     # ETISS build variants
│   └── example-builds.json   # Example build profiles
├── scripts/
│   ├── common.sh            # Shared utilities
│   ├── build-etiss.sh       # Build ETISS
│   ├── build-examples.sh    # Build examples
│   └── run-benchmark.sh     # Run benchmarks
├── tools/
│   └── profiler.py          # Main benchmarking tool
└── results/                 # Generated results
    └── jit_stats/           # JSON statistics
```

## Examples

### Basic Benchmark

```bash
./tools/profiler.py \
    --programs hello_world \
    --jits TCC
```

### Comprehensive Study

```bash
./tools/profiler.py \
    --programs dhrystone coremark tvm_vww \
    --profile default \
    --etiss-variant default \
    --jits TCC GCC LLVM \
    --block-sizes 50 100 200 \
    --experiment-name comprehensive_study \
    --output results/comprehensive.json
```

### Compare Configurations

```bash
# Test multiple profiles and variants
./tools/profiler.py \
    --profile default_runs1 default_runs4 default_runs16 \
    --etiss-variant default profile \
    --programs tvm_vww \
    --jits TCC \
    --experiment-name scaling_study
```

## Troubleshooting

### `jq: command not found`

Install jq:
```bash
# macOS
brew install jq

# Linux
apt-get install jq
yum install jq   
```

### Build Failures

Ensure ETISS and examples are built:
```bash
# Build ETISS
./scripts/build-etiss.sh --variant default

# Build examples
./scripts/build-examples.sh --profile default
```

### Missing JSON Stats

Rebuild ETISS with statistics enabled:
```bash
cd $ETISS_ROOT
cmake -B build -DETISS_TRANSLATOR_STAT=ON
cmake --build build -j$(nproc)
```
