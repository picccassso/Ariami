/// Natural (numeric-aware) path ordering for folder playlist entries.
///
/// Plain lexicographic sorting puts "12 - Song" between "119 - Song" and
/// "120 - Song"; natural ordering compares digit runs by value, so numbered
/// files order the way humans expect regardless of zero-padding
/// (2 < 10 < 100). Non-digit runs compare as plain strings.
int compareNaturalPath(String a, String b) {
  var i = 0;
  var j = 0;

  bool isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);

    if (isDigit(ca) && isDigit(cb)) {
      final startA = i;
      final startB = j;
      while (i < a.length && isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && isDigit(b.codeUnitAt(j))) {
        j++;
      }
      // Compare by numeric value: skip leading zeros, then by length,
      // then digit-by-digit. Avoids int parsing overflow on absurd runs.
      var da = startA;
      var db = startB;
      while (da < i - 1 && a.codeUnitAt(da) == 0x30) {
        da++;
      }
      while (db < j - 1 && b.codeUnitAt(db) == 0x30) {
        db++;
      }
      final lenA = i - da;
      final lenB = j - db;
      if (lenA != lenB) return lenA - lenB;
      for (; da < i; da++, db++) {
        final diff = a.codeUnitAt(da) - b.codeUnitAt(db);
        if (diff != 0) return diff;
      }
      // Equal values: shorter (less-padded) run first for determinism.
      final padDiff = (i - startA) - (j - startB);
      if (padDiff != 0) return padDiff;
      continue;
    }

    if (ca != cb) return ca - cb;
    i++;
    j++;
  }

  return (a.length - i) - (b.length - j);
}
