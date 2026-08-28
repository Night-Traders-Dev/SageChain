# t02 — bigint arithmetic incl. beyond-double-precision values (plan §6)
import orbit.core.bigint as bi

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

check("norm", bi.bi_norm("0007") == "7")
check("zero", bi.bi_is_zero("0000"))
check("cmp-len", bi.bi_cmp("100", "99") == 1)
check("cmp-eq", bi.bi_cmp("42", "42") == 0)
check("cmp-lex", bi.bi_cmp("99", "100") == -1)
check("add-carry", bi.bi_add("99999999999999999999", "1") == "100000000000000000000")
check("add-simple", bi.bi_add("123", "456") == "579")
check("sub-borrow", bi.bi_sub("100000000000000000000", "1") == "99999999999999999999")
check("sub-to-zero", bi.bi_is_zero(bi.bi_sub("500", "500")))
check("mul-small", bi.bi_mul_small("99999999", 999) == "99899999001")
check("mul-big", bi.bi_mul("8200000", "1000000000000000000000") == "8200000000000000000000000000")
check("mul-by-zero", bi.bi_mul("12345678901234567890", "0") == "0")

let qr = bi.bi_divmod("10000000000000000000000", "100000000000000000")
check("div-exact", qr[0] == "100000" and qr[1] == "0")
let qr2 = bi.bi_divmod("1000001", "1000000")
check("div-rem", qr2[0] == "1" and qr2[1] == "1")

# supply-scale sanity: TOTAL = 100B ORBIT in base units = 1e19
let total = bi.bi_mul("100000000000", "100000000")
check("total-supply-units", total == "10000000000000000000")
check("total-above-double", len(total) > 16)

print("t02 bigint: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t02 FAILED"
