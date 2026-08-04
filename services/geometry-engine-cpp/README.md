# geometry-engine-cpp

C++20 geometry expansion service (Milestone 0 skeleton). Expands glyph
blueprints into explicit line segments in later milestones.

## Commands

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release   # configure
cmake --build build                              # build
ctest --test-dir build --output-on-failure       # tests
clang-format -i src/*.cpp include/geometry_engine/*.hpp tests/*.cpp
```

## Coverage

CI builds with `-DENABLE_COVERAGE=ON` and enforces a 90% line-coverage
threshold via gcovr. The `banner` CTest case executes the real binary so
`main()` is covered.
