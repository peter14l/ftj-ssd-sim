CHANGES (automated by Copilot CLI)

Summary of edits performed:

1) Thread-safety hardening (include/ftj_engine.hpp, src/ftj_engine.cpp)
   - Converted page_writes_ vector to std::vector<std::atomic<uint32_t>>
   - Made performance counters atomic: total_reads_, total_writes_, corrected_errors_, uncorrectable_errors_, total_bit_flips_
   - Updated Read/Write, GetMaxWearPercentage, InjectHeavyWear to use atomic loads/stores and fetch_add
   - Added <atomic> include where necessary

2) Tests & CI scaffolding
   - Added src/tests.cpp containing unit tests for ECC, lock-free queue, and concurrent R/W smoke test
   - Added ftj_tests target to CMakeLists.txt
   - Added scratch/ci.yml (CI workflow) for reference — place into .github/workflows/ci.yml

3) Repo hygiene
   - Updated .gitignore to exclude build artifacts and scratch logs
   - Added scratch/LICENSING.md with guidance on WinFsp/GPL vs proprietary IP

Notes / follow-ups:
- Please run full static analysis (cppcheck/clang-tidy) and a sanitizers-enabled build (TSAN/ASAN) locally or in CI — environment here prevented running those tools.
- Verify no other non-permissive third-party source files exist in the tree (e.g., sample WinFsp GPL code). If present, either remove or properly license them.
- Suggested git workflow provided in scratch/git_commands.txt to finish committing and remove build artifacts from index.
