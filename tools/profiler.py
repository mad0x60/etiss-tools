#!/usr/bin/env python3
"""
ETISS Profiling Tool - macOS Compatible

This tool automates building and running ETISS benchmarks with different
configurations for profiling and performance analysis.
"""

import os
import re
import subprocess
import argparse
import json
from pathlib import Path
from typing import Optional, List, Tuple, Dict
from dataclasses import dataclass, asdict
from datetime import datetime

# Configuration
SCRIPTS_ROOT = Path(__file__).parent.parent
CONFIG_FILE = SCRIPTS_ROOT / "config" / "env.conf"
ETISS_BUILDS_JSON = SCRIPTS_ROOT / "config" / "etiss-builds.json"
EXAMPLE_BUILDS_JSON = SCRIPTS_ROOT / "config" / "example-builds.json"


def load_available_profiles() -> Tuple[List[str], List[str]]:
    """Load available profiles from JSON config files"""
    example_profiles = []
    etiss_variants = []
    
    # Load example profiles
    with open(EXAMPLE_BUILDS_JSON, 'r') as f:
        example_config = json.load(f)
        example_profiles = list(example_config['builds'].keys())
    
    # Load ETISS variants
    with open(ETISS_BUILDS_JSON, 'r') as f:
        etiss_config = json.load(f)
        etiss_variants = list(etiss_config['builds'].keys())
    
    return example_profiles, etiss_variants


def load_env() -> Dict[str, str]:
    """Load environment from bash config file"""
    env = os.environ.copy()
    
    # Source bash config and extract variables
    cmd = f"source {CONFIG_FILE} && env"
    proc = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, executable='/bin/bash'
    )
    
    for line in proc.stdout.split('\n'):
        if '=' in line:
            key, _, value = line.partition('=')
            env[key] = value
    
    return env


# Load environment
ENV = load_env()
ETISS_ROOT = Path(ENV.get('ETISS_ROOT', '/Users/mohamed/thesis/etiss'))
EXAMPLES_ROOT = Path(ENV.get('EXAMPLES_ROOT', '/Users/mohamed/thesis/etiss_riscv_examples'))
SCRIPTS_DIR = SCRIPTS_ROOT / 'scripts'
RESULTS_DIR = SCRIPTS_ROOT / 'results'


@dataclass
class BenchmarkResult:
    """Store benchmark execution results"""
    # Configuration
    program: str
    profile: str
    etiss_variant: str
    jit: str
    fast_jit: Optional[str]
    block_size: int
    optimization_threads: Optional[int] = None
    
    # Basic performance metrics
    mips_estimated: float = 0.0
    mips_corrected: float = 0.0
    sim_time: float = 0.0
    wall_time: float = 0.0
    cpu_cycles: int = 0
    cpu_time_simulated: float = 0.0
    
    # Compilation statistics
    unique_blocks_compiled: int = 0
    fast_jit_blocks: int = 0
    optimizing_jit_blocks: int = 0
    
    # Timing statistics (in seconds)
    total_compilation_time_s: float = 0.0
    fast_jit_compilation_time_s: float = 0.0
    optimizing_jit_compilation_time_s: float = 0.0
    block_execution_time_ms: float = 0.0
    
    # Compilation time per block (milliseconds)
    avg_fast_jit_time_ms: float = 0.0
    avg_opt_jit_time_ms: float = 0.0
    fast_jit_speedup: float = 0.0
    
    # Time breakdown percentages
    compilation_percentage: float = 0.0
    execution_percentage: float = 0.0
    
    # Background optimization
    blocks_optimized: int = 0
    blocks_switched: int = 0
    optimization_success_rate: float = 0.0
    switch_rate: float = 0.0
    
    # Execution statistics
    total_block_executions: int = 0
    fast_jit_executions: int = 0
    optimized_executions: int = 0
    fast_jit_exec_percentage: float = 0.0
    optimized_exec_percentage: float = 0.0
    avg_executions_before_switch: int = 0
    
    # Cache performance
    total_cache_lookups: int = 0
    cache_sequential_hits: int = 0
    cache_branch_hits: int = 0
    cache_misses: int = 0
    cache_hit_rate: float = 0.0
    cache_miss_rate: float = 0.0
    
    # File paths
    profiling_report_path: Optional[Path] = None
    stats_json_path: Optional[Path] = None
    category_breakdown: Optional[Dict] = None
    
    def to_dict(self) -> dict:
        result = asdict(self)
        # Convert Path to string for JSON serialization
        if result['profiling_report_path']:
            result['profiling_report_path'] = str(result['profiling_report_path'])
        if result['stats_json_path']:
            result['stats_json_path'] = str(result['stats_json_path'])
        return result


class BenchmarkRunner:
    """Run and profile ETISS benchmarks"""
    
    def __init__(
        self,
        profile: str = 'default',
        etiss_variant: str = 'default',
        gcc_opt_level: str = '3',
        llvm_opt_level: str = '3',
        experiment_name: Optional[str] = None
    ):
        self.profile = profile
        # Add etiss_ prefix if not already present (for compatibility with build scripts)
        if not etiss_variant.startswith('etiss_'):
            self.etiss_variant = f'etiss_{etiss_variant}'
        else:
            self.etiss_variant = etiss_variant
        # Store variant without etiss_ prefix for display purposes
        self.etiss_variant_name = etiss_variant if not etiss_variant.startswith('etiss_') else etiss_variant.replace('etiss_', '')
        self.gcc_opt_level = gcc_opt_level
        self.llvm_opt_level = llvm_opt_level
        self.experiment_name = experiment_name
        self.build_script = SCRIPTS_DIR / 'build-examples.sh'
        self.etiss_build_script = SCRIPTS_DIR / 'build-etiss.sh'
        self.run_script = SCRIPTS_DIR / 'run-benchmark.sh'
        
        # Ensure results directory exists
        RESULTS_DIR.mkdir(exist_ok=True)
        
        # Set up jit_stats directory with optional experiment subdirectory
        if experiment_name:
            self.jit_stats_dir = RESULTS_DIR / 'jit_stats' / experiment_name
        else:
            self.jit_stats_dir = RESULTS_DIR / 'jit_stats'
        self.jit_stats_dir.mkdir(parents=True, exist_ok=True)
    
    def generate_stats_filename(
        self, 
        program: str, 
        jit: str, 
        fast_jit: Optional[str], 
        optimization_threads: Optional[int], 
        block_size: int
    ) -> str:
        """Generate descriptive filename for JIT stats JSON"""
        parts = [
            program,
            f"profile-{self.profile}",
            f"variant-{self.etiss_variant_name}",
            f"jit-{jit}"
        ]
        
        if fast_jit:
            parts.append(f"fast-{fast_jit}")
            if optimization_threads is not None:
                parts.append(f"threads-{optimization_threads}")
        
        parts.append(f"block-{block_size}")
        
        # Add timestamp for uniqueness
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        parts.append(timestamp)
        
        return "_".join(parts) + ".json"
    
    def build_etiss(self, clean: bool = False):
        """Build ETISS with specified variant"""
        cmd = [str(self.etiss_build_script), '--variant', self.etiss_variant]
        if clean:
            cmd.append('--clean')
        
        print(f"Building ETISS variant '{self.etiss_variant}'...")
        subprocess.run(cmd, check=True)
    
    def build_program(self, program: str, clean: bool = False):
        """Build a specific program with current profile"""
        cmd = [str(self.build_script), '--profile', self.profile, '--program', program]
        if clean:
            cmd.append('--clean')
        
        print(f"Building {program} with profile '{self.profile}'...")
        subprocess.run(cmd, check=True)
    
    def run_benchmark(
        self,
        program: str,
        jit: str = 'TCC',
        fast_jit: Optional[str] = None,
        block_size: int = 100,
        optimization_threads: Optional[int] = None
    ) -> BenchmarkResult:
        """Run benchmark and extract metrics"""
        return self._run_benchmark_regular(program, jit, fast_jit, block_size, optimization_threads)
    
    def _run_benchmark_regular(
        self,
        program: str,
        jit: str = 'TCC',
        fast_jit: Optional[str] = None,
        block_size: int = 100,
        optimization_threads: Optional[int] = None
    ) -> BenchmarkResult:
        """Run benchmark without profiling, using JSON stats export."""
        # Generate JSON output filename
        json_filename = self.generate_stats_filename(
            program, jit, fast_jit, optimization_threads, block_size
        )
        json_path = self.jit_stats_dir / json_filename
        
        cmd = [
            str(self.run_script),
            '--program', program,
            '--profile', self.profile,
            '--etiss-variant', self.etiss_variant,
            '--jit', jit,
            '--block-size', str(block_size),
            '--gcc-opt-level', self.gcc_opt_level,
            '--llvm-opt-level', self.llvm_opt_level,
            '--jit-stats-json', str(json_path)
        ]
        if fast_jit:
            cmd.extend(['--fast-jit', fast_jit])
        if optimization_threads is not None:
            cmd.extend(['--optimization-threads', str(optimization_threads)])
        
        fast_jit_str = f", fast: {fast_jit}" if fast_jit else ""
        opt_threads_str = f", threads: {optimization_threads}" if optimization_threads is not None else ""
        print(f"Running {program} (JIT: {jit}{fast_jit_str}{opt_threads_str}, block: {block_size})...")
        proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        # Print any warnings or errors from stderr
        if proc.stderr:
            print(f"  [stderr]: {proc.stderr}")
        
        # Parse JSON stats file
        if json_path.exists():
            with open(json_path) as f:
                data = json.load(f)
            
            # Extract data from JSON structure
            metadata = data.get('metadata', {})
            perf = data.get('performance', {})
            comp = data.get('compilation', {})
            exec_stats = data.get('execution', {})
            opt = data.get('optimization', {})
            cache = data.get('cache', {})
            
            return BenchmarkResult(
                program=program,
                profile=self.profile,
                etiss_variant=self.etiss_variant,
                jit=jit,
                fast_jit=fast_jit,
                block_size=block_size,
                optimization_threads=optimization_threads,
                
                # Performance metrics
                mips_estimated=perf.get('mips_estimated', 0.0),
                mips_corrected=perf.get('mips_corrected', 0.0),
                sim_time=perf.get('simulation_time_s', 0.0),
                wall_time=perf.get('wall_time_s', 0.0),
                cpu_cycles=int(perf.get('cpu_cycles', 0)),
                cpu_time_simulated=perf.get('cpu_time_s', 0.0),
                
                # Compilation statistics
                unique_blocks_compiled=comp.get('unique_blocks', 0),
                fast_jit_blocks=comp.get('fast_jit_blocks', 0),
                optimizing_jit_blocks=comp.get('optimizing_jit_blocks', 0),
                total_compilation_time_s=comp.get('total_time_s', 0.0),
                fast_jit_compilation_time_s=comp.get('fast_jit_time_s', 0.0),
                optimizing_jit_compilation_time_s=comp.get('optimizing_jit_time_s', 0.0),
                avg_fast_jit_time_ms=comp.get('avg_fast_jit_time_ms', 0.0),
                avg_opt_jit_time_ms=comp.get('avg_optimizing_jit_time_ms', 0.0),
                fast_jit_speedup=comp.get('fast_jit_speedup', 0.0),
                compilation_percentage=comp.get('compilation_percentage', 0.0),
                execution_percentage=comp.get('execution_percentage', 0.0),
                
                # Execution statistics
                total_block_executions=exec_stats.get('total_block_executions', 0),
                fast_jit_executions=exec_stats.get('fast_jit_executions', 0),
                optimized_executions=exec_stats.get('optimized_executions', 0),
                fast_jit_exec_percentage=exec_stats.get('fast_jit_exec_percentage', 0.0),
                optimized_exec_percentage=exec_stats.get('optimized_exec_percentage', 0.0),
                block_execution_time_ms=exec_stats.get('block_execution_time_ms', 0.0),
                
                # Optimization
                blocks_optimized=opt.get('blocks_optimized', 0),
                blocks_switched=opt.get('blocks_switched', 0),
                optimization_success_rate=opt.get('optimization_success_rate', 0.0),
                switch_rate=opt.get('switch_rate', 0.0),
                avg_executions_before_switch=opt.get('avg_executions_before_switch', 0),
                
                # Cache performance
                total_cache_lookups=cache.get('total_lookups', 0),
                cache_sequential_hits=cache.get('sequential_hits', 0),
                cache_branch_hits=cache.get('branch_hits', 0),
                cache_misses=cache.get('misses', 0),
                cache_hit_rate=cache.get('hit_rate', 0.0),
                cache_miss_rate=cache.get('miss_rate', 0.0),
                
                # File paths
                stats_json_path=json_path
            )
        else:
            # Fallback to regex parsing if JSON file doesn't exist
            print(f"Warning: JSON stats file not found at {json_path}, falling back to regex parsing")
            output = proc.stdout
            mips_estimated = self._extract_float(output, r"MIPS \(estimated\): ([\d.e+-]+)")
            mips_corrected = self._extract_float(output, r"MIPS \(corrected\): ([\d.e+-]+)")
            sim_time = self._extract_float(output, r"Simulation Time: ([\d.e+-]+)s")
            wall_time = self._extract_float(output, r"Wallclock Time: ([\d.e+-]+)s")
            cycles = self._extract_int(output, r"CPU Cycles \(estimated\): ([\d.e+-]+)")
            
            return BenchmarkResult(
                program=program,
                profile=self.profile,
                etiss_variant=self.etiss_variant,
                jit=jit,
                fast_jit=fast_jit,
                block_size=block_size,
                mips_estimated=mips_estimated,
                mips_corrected=mips_corrected,
                sim_time=sim_time,
                wall_time=wall_time,
                cpu_cycles=cycles,
                optimization_threads=optimization_threads
            )
    
    def get_profile(self, profile_name: str, category: str = "examples") -> Optional[Dict]:
        """Get profile configuration from JSON config files."""
        if category == "etiss":
            config_file = ETISS_BUILDS_JSON
        else:
            config_file = EXAMPLE_BUILDS_JSON
        
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
                if profile_name in config['builds']:
                    # Return the profile dict with the name included
                    profile = config['builds'][profile_name].copy()
                    profile['name'] = profile_name
                    return profile
        except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
            print(f"Error loading profile {profile_name} from {config_file}: {e}")
        
        return None
    
    def _extract_float(self, text: str, pattern: str) -> float:
        """Extract float value from text using regex"""
        match = re.search(pattern, text)
        return float(match.group(1)) if match else 0.0
    
    def _extract_int(self, text: str, pattern: str) -> int:
        """Extract integer value from text using regex"""
        match = re.search(pattern, text)
        return int(float(match.group(1))) if match else 0
    
    def run_experiment(
        self,
        programs: List[str],
        jits: List[str],
        block_sizes: List[int],
        fast_jits: Optional[List[Optional[str]]] = None,
        optimization_threads: Optional[List[int]] = None,
        rebuild: bool = False
    ) -> List[BenchmarkResult]:
        """Run full experiment with multiple configurations"""
        results = []
        
        # Build programs if needed
        if rebuild:
            for program in programs:
                self.build_program(program, clean=True)
        
        # If no fast_jits specified, use [None] to run without fast_jit
        fast_jit_list = fast_jits if fast_jits else [None]
        
        # If no optimization_threads specified, use [None] to use default
        opt_threads_list = optimization_threads if optimization_threads else [None]
        
        # Run all combinations
        for program in programs:
            for jit in jits:
                for fast_jit in fast_jit_list:
                    for opt_threads in opt_threads_list:
                        for block_size in block_sizes:
                            try:
                                result = self.run_benchmark(program, jit, fast_jit, block_size, opt_threads)
                                results.append(result)
                                fast_jit_str = f", fast: {result.fast_jit}" if result.fast_jit else ""
                                opt_threads_str = f", threads: {result.optimization_threads}" if result.optimization_threads is not None else ""
                                print(f"  → MIPS (estimated): {result.mips_estimated:.4f}, MIPS (corrected): {result.mips_corrected:.4f}, Wall time: {result.wall_time:.4f}s")
                            except subprocess.CalledProcessError as e:
                                print(f"  → FAILED: {e}")
                                if e.stderr:
                                    print(f"  → Error output: {e.stderr}")
                                if e.stdout:
                                    print(f"  → Standard output: {e.stdout}")
        
        return results
    
    def save_results(self, results: List[BenchmarkResult], output_file: Path):
        """Save results to JSON file"""
        data = {
            'profile': self.profile,
            'etiss_variant': self.etiss_variant,
            'results': [r.to_dict() for r in results]
        }
        
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"\nResults saved to: {output_file}")


def main():
    # Load available profiles from config
    example_profiles, etiss_variants = load_available_profiles()
    
    parser = argparse.ArgumentParser(
        description='ETISS Profiling Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    # Program selection
    parser.add_argument(
        '--programs', nargs='+', default=['hello_world'],
        help='Programs to run (default: hello_world)'
    )
    
    # Configuration
    parser.add_argument(
        '--profile', nargs='+', default=['default'],
        choices=example_profiles,
        help=f'Examples build profile(s) to test (default: default). Available: {", ".join(example_profiles[:5])}...'
    )
    parser.add_argument(
        '--etiss-variant', nargs='+', default=['default'],
        choices=etiss_variants,
        help=f'ETISS build variant(s) to test (default: default). Available: {", ".join(etiss_variants[:5])}...'
    )
    
    # JIT configuration
    parser.add_argument(
        '--jits', nargs='+', default=['TCC'],
        choices=['GCC', 'TCC', 'LLVM'],
        help='JIT compilers to test (default: TCC)'
    )
    parser.add_argument(
        '--block-sizes', type=int, nargs='+', default=[100],
        help='Block sizes to test (default: 100)'
    )
    parser.add_argument(
        '--gcc-opt-level', default='3',
        choices=['0', '1', '2', '3', 's', 'fast'],
        help='GCC JIT optimization level (default: 3)'
    )
    parser.add_argument(
        '--llvm-opt-level', default='3',
        choices=['0', '1', '2', '3', 's', 'z', 'fast'],
        help='LLVM JIT optimization level (default: 3)'
    )
    parser.add_argument(
        '--fast-jits', nargs='+', default=None,
        choices=['GCC', 'TCC', 'LLVM', 'None'],
        help='Fast JIT compiler(s) for jit.fast_type (optional, can specify multiple, use "None" to test without fast JIT)'
    )
    parser.add_argument(
        '--optimization-threads', type=int, nargs='+', default=None,
        help='Number of background optimization threads (can specify multiple values to test)'
    )
    
    # Build options
    parser.add_argument(
        '--rebuild', action='store_true',
        help='Rebuild programs before running'
    )
    parser.add_argument(
        '--rebuild-etiss', action='store_true',
        help='Rebuild ETISS before running'
    )
    
    # Output
    parser.add_argument(
        '--output', type=Path,
        help='Output file for results (JSON format)'
    )
    parser.add_argument(
        '--experiment-name', type=str,
        help='Experiment name for organizing results into subdirectories (optional)'
    )
    
    args = parser.parse_args()
    
    # Process fast_jits: convert "None" string to Python None
    fast_jits = None
    if args.fast_jits:
        fast_jits = [None if fj == 'None' else fj for fj in args.fast_jits]
    
    # Build ETISS variants if requested (do this once before running experiments)
    if args.rebuild_etiss:
        built_variants = set()
        for etiss_variant in args.etiss_variant:
            if etiss_variant not in built_variants:
                # Create a temporary runner just to build ETISS
                temp_runner = BenchmarkRunner(
                    args.profile[0],  # Use first profile (doesn't matter for ETISS build)
                    etiss_variant,
                    gcc_opt_level=args.gcc_opt_level,
                    llvm_opt_level=args.llvm_opt_level,
                    experiment_name=args.experiment_name
                )
                temp_runner.build_etiss(clean=True)
                built_variants.add(etiss_variant)
    
    # Run experiments for all combinations of profiles and etiss variants
    all_results = []
    
    for etiss_variant in args.etiss_variant:
        for profile in args.profile:
            print(f"\n{'='*60}")
            print(f"Testing profile: {profile}, ETISS variant: {etiss_variant}")
            print(f"{'='*60}\n")
            
            # Initialize runner for this combination
            runner = BenchmarkRunner(
                profile,
                etiss_variant,
                gcc_opt_level=args.gcc_opt_level,
                llvm_opt_level=args.llvm_opt_level,
                experiment_name=args.experiment_name
            )
            
            # Run experiment
            results = runner.run_experiment(
                programs=args.programs,
                jits=args.jits,
                block_sizes=args.block_sizes,
                fast_jits=fast_jits,
                optimization_threads=args.optimization_threads,
                rebuild=args.rebuild
            )
            
            all_results.extend(results)
    
    # Save results if output specified
    if args.output:
        # Save all results with metadata about all profiles and variants tested
        data = {
            'profiles': args.profile,
            'etiss_variants': args.etiss_variant,
            'results': [r.to_dict() for r in all_results]
        }
        
        with open(args.output, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"\nResults saved to: {args.output}")
    
    # Print summary
    print(f"\n" + "=" * 60)
    print(f"Completed {len(all_results)} benchmark runs")
    print(f"  Profiles tested: {', '.join(args.profile)}")
    print(f"  ETISS variants tested: {', '.join(args.etiss_variant)}")
    print("=" * 60)


if __name__ == '__main__':
    main()
