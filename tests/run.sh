#!/bin/bash
# zigparse test suite
set -e

BIN="./zigparse"
PASS=0
FAIL=0

pass() { echo -e "\033[32m  ✓ $1\033[0m"; PASS=$((PASS + 1)); }
fail() { echo -e "\033[31m  ✗ $1\033[0m"; FAIL=$((FAIL + 1)); }

echo -e "\n\033[1;34m═══ zigparse test suite\033[0m\n"

# ─── CSV ───
echo -e "\033[1mCSV parser\033[0m"

cat > /tmp/t.csv <<'EOF'
name,age,city
Alice,30,Moscow
"Bob, Jr",25,"New York"
EOF

OUT=$($BIN csv /tmp/t.csv 2>&1)
echo "$OUT" | grep -q "name" && pass "Header row printed" || fail "Header missing"
echo "$OUT" | grep -q "Alice" && pass "Data row: Alice" || fail "Alice missing"
echo "$OUT" | grep -q "Bob, Jr" && pass "Quoted field with comma" || fail "Quoted field failed"
echo "$OUT" | grep -q "rows" && pass "Row count shown" || fail "Row count missing"

# ─── TSV ───
echo -e "\n\033[1mTSV parser\033[0m"

printf "a\tb\tc\n1\t2\t3\n" > /tmp/t.tsv
OUT=$($BIN tsv /tmp/t.tsv 2>&1)
echo "$OUT" | grep -q "a" && pass "TSV header" || fail "TSV header missing"
echo "$OUT" | grep -q "1" && pass "TSV data" || fail "TSV data missing"

# ─── Stdin ───
echo -e "\n\033[1mStdin support\033[0m"

OUT=$(echo "x,y\n1,2" | $BIN csv - 2>&1)
echo "$OUT" | grep -q "x" && pass "CSV from stdin" || fail "CSV stdin failed"

OUT=$(printf "p\tq\n3\t4\n" | $BIN tsv - 2>&1)
echo "$OUT" | grep -q "p" && pass "TSV from stdin" || fail "TSV stdin failed"

# ─── Detect ───
echo -e "\n\033[1mAuto-detect\033[0m"

OUT=$($BIN detect /tmp/t.csv 2>&1)
echo "$OUT" | grep -q "CSV" && pass "Detect CSV" || fail "CSV not detected"

OUT=$($BIN detect /tmp/t.tsv 2>&1)
echo "$OUT" | grep -q "TSV" && pass "Detect TSV" || fail "TSV not detected"

# JSON detection
echo '{"a":1}' > /tmp/t.json
OUT=$($BIN detect /tmp/t.json 2>&1)
echo "$OUT" | grep -q "JSON" && pass "Detect JSON" || fail "JSON not detected"

# ─── PDF ───
echo -e "\n\033[1mPDF detection\033[0m"

# Create minimal PDF
printf '%%PDF-1.0\n1 0 obj\n<< >>\nstream\nBT\n(Hello World) Tj\nET\nendstream\nendobj\n' > /tmp/t.pdf
OUT=$($BIN detect /tmp/t.pdf 2>&1)
echo "$OUT" | grep -q "PDF" && pass "Detect PDF" || fail "PDF not detected"

# ─── Text ───
echo -e "\n\033[1mText extraction\033[0m"

printf 'Hello\x00\x01World\x00Test' > /tmp/t.bin
OUT=$($BIN text /tmp/t.bin 2>&1)
echo "$OUT" | grep -q "Hello" && pass "Text extraction" || fail "Text extraction failed"

# ─── Edge cases ───
echo -e "\n\033[1mEdge cases\033[0m"

# Empty CSV
echo "" > /tmp/empty.csv
$BIN csv /tmp/empty.csv > /dev/null 2>&1 && pass "Empty file handled" || fail "Empty file crashed"

# Large CSV (1000 rows)
python3 -c "
print('id,value')
for i in range(1000):
    print(f'{i},data_{i}')
" > /tmp/large.csv
OUT=$($BIN csv /tmp/large.csv 2>&1)
echo "$OUT" | grep -q "1001 rows" && pass "1000-row CSV parsed" || fail "Large CSV failed"

# ─── Summary ───
echo -e "\n\033[1;34m═══ Results\033[0m"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"

if [ "$FAIL" -eq 0 ]; then
    echo -e "\n\033[32mAll tests passed!\033[0m"
else
    echo -e "\n\033[31m$FAIL tests failed\033[0m"
    exit 1
fi

# Cleanup
rm -f /tmp/t.csv /tmp/t.tsv /tmp/t.json /tmp/t.pdf /tmp/t.bin /tmp/empty.csv /tmp/large.csv
