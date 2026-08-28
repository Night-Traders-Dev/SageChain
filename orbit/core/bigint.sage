# orbit/core/bigint.sage — non-negative decimal-string big integers
# Orbit Blockchain | Protocol v1 | Status: implemented
#
# WHY: plan §6 forbids binary floats for balances/consensus. Sage numbers are
# doubles (exact only below 2^53 ~ 9e15) while supply is 1e19 base units.
# All consensus amounts are therefore canonical decimal STRINGS and every
# arithmetic operation goes through this module.

proc bi_norm(a):
    # strip leading zeros; "" -> "0"
    let s = a
    var i = 0
    while i < len(s) - 1 and s[i] == "0":
        i = i + 1
    return slice(s, i, len(s))

proc bi_is_zero(a):
    return bi_norm(a) == "0"

# a<b -> -1 ; equal -> 0 ; a>b -> 1   (both normalized)
proc bi_cmp(a, b):
    let x = bi_norm(a)
    let y = bi_norm(b)
    if len(x) < len(y):
        return -1
    if len(x) > len(y):
        return 1
    if x < y:
        return -1
    if x > y:
        return 1
    return 0

proc bi_add(a, b):
    var i = len(a) - 1
    var j = len(b) - 1
    var carry = 0
    let out = []
    while i >= 0 or j >= 0 or carry > 0:
        let da = 0
        let db = 0
        if i >= 0:
            da = ord(a[i]) - 48
            i = i - 1
        if j >= 0:
            db = ord(b[j]) - 48
            j = j - 1
        let s = da + db + carry
        push(out, chr(48 + s % 10))
        carry = int(s / 10)
    let res = []
    var k = len(out) - 1
    while k >= 0:
        push(res, out[k])
        k = k - 1
    return join(res, "")

# requires a >= b (both normalized)
proc bi_sub(a, b):
    var i = len(a) - 1
    var j = len(b) - 1
    var borrow = 0
    let out = []
    while i >= 0:
        let da = ord(a[i]) - 48 - borrow
        let db = 0
        if j >= 0:
            db = ord(b[j]) - 48
            j = j - 1
        var d = da - db
        if d < 0:
            d = d + 10
            borrow = 1
        else:
            borrow = 0
        push(out, chr(48 + d))
        i = i - 1
    let res = []
    var k = len(out) - 1
    while k >= 0:
        push(res, out[k])
        k = k - 1
    return bi_norm(join(res, ""))

proc bi_mul_small(a, m):
    # m must satisfy 0 <= m <= 999999999 (keeps products inside double exactness)
    if m < 0 or m > 999999999:
        raise "bi_mul_small: multiplier out of range"
    if bi_is_zero(a) or m == 0:
        return "0"
    var carry = 0
    let out = []
    var i = len(a) - 1
    while i >= 0:
        let prod = (ord(a[i]) - 48) * m + carry
        push(out, chr(48 + prod % 10))
        carry = int(prod / 10)
        i = i - 1
    while carry > 0:
        push(out, chr(48 + carry % 10))
        carry = int(carry / 10)
    let res = []
    var k = len(out) - 1
    while k >= 0:
        push(res, out[k])
        k = k - 1
    return join(res, "")

proc bi_mul(a, b):
    # schoolbook; per-cell sums stay tiny for our digit counts
    if bi_is_zero(a) or bi_is_zero(b):
        return "0"
    let n = len(a)
    let m = len(b)
    let cell = []
    let total = n + m
    var z = 0
    while z < total:
        push(cell, 0)
        z = z + 1
    var i = n - 1
    while i >= 0:
        let di = ord(a[i]) - 48
        var j = m - 1
        while j >= 0:
            let dj = ord(b[j]) - 48
            cell[i + j + 1] = cell[i + j + 1] + di * dj
            j = j - 1
        i = i - 1
    var carry = 0
    var p = total - 1
    while p >= 0:
        let v = cell[p] + carry
        cell[p] = v % 10
        carry = int(v / 10)
        p = p - 1
    let res = []
    for dgt in cell:
        push(res, chr(48 + dgt))
    return bi_norm(join(res, ""))

# returns [quotient, remainder] as strings; b != "0"
proc bi_divmod(a, b):
    let divisor = bi_norm(b)
    if bi_is_zero(divisor):
        raise "bi_divmod: division by zero"
    let q_digits = []
    var rem = "0"
    var idx = 0
    let dividend = bi_norm(a)
    while idx < len(dividend):
        rem = bi_norm(rem + dividend[idx])
        # find largest dcnt in 0..9 with divisor*dcnt <= rem
        var dcnt = 0
        var acc = "0"
        while dcnt < 9:
            let nxt = bi_add(acc, divisor)
            if bi_cmp(nxt, rem) <= 0:
                acc = nxt
                dcnt = dcnt + 1
            else:
                break
        push(q_digits, chr(48 + dcnt))
        if dcnt > 0:
            rem = bi_sub(rem, acc)
        idx = idx + 1
    let q = bi_norm(join(q_digits, ""))
    return [q, rem]

proc bi_div(a, b):
    let qr = bi_divmod(a, b)
    return qr[0]

proc bi_mod(a, b):
    let qr = bi_divmod(a, b)
    return qr[1]

proc bi_from_number(n):
    if n != int(n) or n < 0:
        raise "bi_from_number: needs non-negative integral input"
    if n >= 9007199254740992:
        raise "bi_from_number: above 2^53 precision would be lost"
    return str(int(n))

proc bi_to_number(a):
    # safe only when caller knows the value fits under 2^53
    let norm = bi_norm(a)
    if len(norm) > 15:
        raise "bi_to_number: too large for exact double conversion"
    var acc = 0
    var i = 0
    while i < len(norm):
        acc = acc * 10 + (ord(norm[i]) - 48)
        i = i + 1
    return acc

proc bi_pow10(k):
    let out = ["1"]
    var i = 0
    while i < k:
        push(out, "0")
        i = i + 1
    return join(out, "")
