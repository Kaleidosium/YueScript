#!/bin/bash
# Test Compilation Functionality for YueScript CLI
# Tests: File compilation, directory compilation, output options

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cli_test_helper.sh"

# Check binary
check_yue_binary

# Setup test environment
setup_test_env
TMP_DIR=$(get_test_tmp_dir)

echo "========================================"
echo "Testing Compilation Functionality"
echo "========================================"
echo ""

# Test 1: Compile a simple file to stdout
echo "Testing simple file compilation to stdout..."
cat > "$TMP_DIR/simple.yue" << 'EOF'
print "Hello, World!"
EOF

assert_output_contains "Compile simple file to stdout" "print" $YUE_BIN -p "$TMP_DIR/simple.yue"

# Test 2: Compile a simple file to disk
echo ""
echo "Testing file compilation to disk..."
cat > "$TMP_DIR/test1.yue" << 'EOF'
x = 1 + 2
print x
EOF

assert_success "Compile test1.yue to disk" $YUE_BIN "$TMP_DIR/test1.yue"
assert_file_exists "Output file test1.lua should exist" "$TMP_DIR/test1.lua"

# Test 3: Compile with -o option
echo ""
echo "Testing compilation with -o option..."
cat > "$TMP_DIR/test2.yue" << 'EOF'
x = 10
print x
EOF

assert_success "Compile with -o option" $YUE_BIN -o "$TMP_DIR/output.lua" "$TMP_DIR/test2.yue"
assert_file_exists "Custom output file should exist" "$TMP_DIR/output.lua"

# Test 4: Compile directory with -t option (target directory)
echo ""
echo "Testing compilation with -t option..."
mkdir -p "$TMP_DIR/src"
mkdir -p "$TMP_DIR/build"
cat > "$TMP_DIR/src/test3.yue" << 'EOF'
print "test"
EOF

assert_success "Compile directory with -t option" $YUE_BIN "$TMP_DIR/src" -t "$TMP_DIR/build"
assert_file_exists "Output should be in target directory" "$TMP_DIR/build/test3.lua"

# Test 5: Compile directory recursively
echo ""
echo "Testing directory compilation..."
mkdir -p "$TMP_DIR/project/src"
mkdir -p "$TMP_DIR/project/build"

cat > "$TMP_DIR/project/src/file1.yue" << 'EOF'
print "file1"
EOF

cat > "$TMP_DIR/project/src/file2.yue" << 'EOF'
print "file2"
EOF

assert_success "Compile entire directory" $YUE_BIN "$TMP_DIR/project/src" -t "$TMP_DIR/project/build"
# Files are compiled directly in target directory, not preserving src subdir
assert_file_exists "file1.lua should exist" "$TMP_DIR/project/build/file1.lua"
assert_file_exists "file2.lua should exist" "$TMP_DIR/project/build/file2.lua"

# Test 6: Compile with line numbers (-l)
echo ""
echo "Testing compilation with line numbers..."
cat > "$TMP_DIR/test_line.yue" << 'EOF'
print "line test"
EOF

assert_success "Compile with line numbers" $YUE_BIN -l "$TMP_DIR/test_line.yue" -o "$TMP_DIR/test_line.lua"
assert_output_contains "Compiled file should have line comment" "yue" cat "$TMP_DIR/test_line.lua"

cat > "$TMP_DIR/test_line_empty_block.yue" << 'EOF'
x = {
	1

	2
}

y =
	a: 1

	b: 2

Z = class
	m: 1

	n: 2
EOF

assert_success "Compile with line numbers for table/class blocks with empty lines" $YUE_BIN -l "$TMP_DIR/test_line_empty_block.yue" -o "$TMP_DIR/test_line_empty_block.lua"
assert_success "Empty lines should not generate standalone line number comments" bash -lc '! grep -Eq "^[[:space:]]*-- [0-9]+$" "$0"' "$TMP_DIR/test_line_empty_block.lua"

# Test 7: Compile with spaces instead of tabs (-s)
echo ""
echo "Testing compilation with spaces..."
cat > "$TMP_DIR/test_spaces.yue" << 'EOF'
x = 1
EOF

assert_success "Compile with spaces option" $YUE_BIN -s "$TMP_DIR/test_spaces.yue" -o "$TMP_DIR/test_spaces.lua"

# Test 8: Compile with minify (-m)
echo ""
echo "Testing compilation with minify..."
cat > "$TMP_DIR/test_minify.yue" << 'EOF'
-- this is a comment
x = 1 + 2
print x
EOF

assert_success "Compile with minify option" $YUE_BIN -m "$TMP_DIR/test_minify.yue" -o "$TMP_DIR/test_minify.lua"
assert_file_exists "Minified file should exist" "$TMP_DIR/test_minify.lua"

# Test 9: Stdin/stdout compilation
echo ""
echo "Testing stdin/stdout compilation..."
echo 'print "stdin test"' | assert_output_contains "Compile from stdin" "print" $YUE_BIN -

# Test 10: Glob variable dumping (-g)
echo ""
echo "Testing global variable dumping..."
cat > "$TMP_DIR/test_globals.yue" << 'EOF'
local x = 1
print unknown_global
EOF

# -g dumps globals in format: NAME LINE COLUMN
assert_output_contains "Dump global variables" "unknown_global" $YUE_BIN -g "$TMP_DIR/test_globals.yue"

# Test 11: Benchmark compilation (-b)
echo ""
echo "Testing benchmark compilation..."
cat > "$TMP_DIR/test_bench.yue" << 'EOF'
print "benchmark"
EOF

assert_output_contains "Benchmark should show compile time" "Compile time:" $YUE_BIN -b "$TMP_DIR/test_bench.yue"

# Test 12: Target version option
echo ""
echo "Testing target version option..."
cat > "$TMP_DIR/test_target.yue" << 'EOF'
print "target test"
EOF

assert_success "Compile with target 5.1" $YUE_BIN "$TMP_DIR/test_target.yue" -o "$TMP_DIR/test_target.lua" --target 5.1
assert_file_exists "Target version compilation should succeed" "$TMP_DIR/test_target.lua"

# Test 13: --path keeps Lua's ';;' default-path insertion point
echo ""
echo "Testing --path default path marker..."
mkdir -p "$TMP_DIR/modules"
cat > "$TMP_DIR/path_marker.yue" << 'EOF'
export macro marker = -> '"default"'
EOF

cat > "$TMP_DIR/modules/path_marker.yue" << 'EOF'
export macro marker = -> '"custom"'
EOF

cat > "$TMP_DIR/path_marker_test.yue" << 'EOF'
import "path_marker" as $
value = $marker!
EOF

YUE_BIN_ABS="$(cd "$(dirname "$YUE_BIN")" && pwd)/$(basename "$YUE_BIN")"
assert_output_contains "Double semicolon inserts the default path in place" 'value = "default"' \
	bash -c 'cd "$1" && "$2" --target 5.1 -c -l -p --path ";;./modules/?.lua" path_marker_test.yue' _ "$TMP_DIR" "$YUE_BIN_ABS"

# Test 14: Lua 5.3 floor division survives rewriting and minification
echo ""
echo "Testing floor division formatting..."
cat > "$TMP_DIR/floor_division.yue" << 'EOF'
x = 7 // 2
print x
EOF

assert_success "Rewrite code with floor division" $YUE_BIN --target 5.3 -r -o "$TMP_DIR/floor_division_rewritten.lua" "$TMP_DIR/floor_division.yue"
assert_output_contains "Rewritten code keeps floor division" "//" cat "$TMP_DIR/floor_division_rewritten.lua"
assert_success "Minify code with floor division" $YUE_BIN --target 5.3 -m -o "$TMP_DIR/floor_division_minified.lua" "$TMP_DIR/floor_division.yue"
assert_output_contains "Minified code keeps floor division" "//" cat "$TMP_DIR/floor_division_minified.lua"

echo ""
print_summary
