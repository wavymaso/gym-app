#!/bin/bash
# Design-system check (DESIGN.md): fails on raw fonts, numeric paddings/spacing and corner-radius
# literals outside Design.swift and Tokens.swift. Justified exceptions: tools/design-allowlist.txt, one
# per line as "path: exact code fragment  # reason". `tools/lint-design.sh counts` prints the totals.
cd "$(dirname "$0")/.."
ALLOW=tools/design-allowlist.txt
pat='\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)\b|\.system\(size:|\.number\([0-9]|\.pageTitle\(|\.padding\((\.[a-zA-Z]+, *)?-?[0-9]+(\.[0-9]+)?\)|\bspacing: *[1-9][0-9.]*|cornerRadius: *[0-9]|\.cornerRadius\([0-9]'
hits=$(grep -rnE "$pat" --include=*.swift Gym GymWidget | grep -v "^Gym/Design.swift:\|^Gym/Tokens.swift:")
if [ "$1" = counts ]; then
  for k in 'font\(\.(largeTitle|title|headline|subheadline|body|callout|footnote|caption)' 'system\(size:|\.number\([0-9]|\.pageTitle\(' 'padding\(' 'spacing:' '[cC]ornerRadius'; do
    printf "%-60s %s\n" "$k" "$(echo "$hits" | grep -cE "$k")"
  done
fi
bad=0
while IFS= read -r h; do
  [ -z "$h" ] && continue
  f=${h%%:*}; code=${h#*:*:}
  ok=0
  while IFS= read -r a; do
    a=${a%%  #*}; af=${a%%: *}; frag=${a#*: }
    [ -z "$a" ] && continue
    if [ "$af" = "$f" ] && { [ "$frag" = "*" ] || [[ "$code" == *"$frag"* ]]; }; then ok=1; break; fi
  done < "$ALLOW"
  [ $ok = 0 ] && { echo "$h"; bad=$((bad+1)); }
done <<< "$hits"
[ $bad = 0 ] && echo "DESIGN LINT PASSED" || echo "DESIGN LINT FAILED: $bad raw values (use Design.swift roles and tokens, or allowlist with a reason)"
[ $bad = 0 ]
