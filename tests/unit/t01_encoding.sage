# t01 — canonical encoding (plan §21, §42)
import orbit.crypto.encoding as enc

let pass = {"n": 0}
let fail = {"n": 0}
proc check(name, cond):
    if cond:
        pass["n"] = pass["n"] + 1
    else:
        fail["n"] = fail["n"] + 1
        print("FAIL: " + name)

check("nil", enc.encode_canonical(nil) == "n")
check("true", enc.encode_canonical(true) == "b1")
check("false", enc.encode_canonical(false) == "b0")
check("int0", enc.encode_canonical(0) == "i0e")
check("int-neg", enc.encode_canonical(-5) == "i-5e")
check("string", enc.encode_canonical("abc") == "s3:abc")
check("empty-string", enc.encode_canonical("") == "s0:")
check("array", enc.encode_canonical([1, "a"]) == "li1es1:ae")
check("empty-array", enc.encode_canonical([]) == "le")

# dict keys MUST be sorted regardless of insertion order (§21)
let d1 = {"b": 2, "a": 1}
let d2 = {"a": 1, "b": 2}
check("dict-sorted", enc.encode_canonical(d1) == enc.encode_canonical(d2))
check("dict-form", enc.encode_canonical(d1) == "ds1:ai1es1:bi2ee")

# nested determinism
let n1 = {"z": [1, {"k": "v"}], "a": nil}
let n2 = {"a": nil, "z": [1, {"k": "v"}]}
check("nested-order-free", enc.encode_canonical(n1) == enc.encode_canonical(n2))

# fractional floats rejected
var threw = false
try:
    enc.encode_canonical(3.14)
catch e:
    threw = true
check("float-rejected", threw)

# huge ints rejected (use bigint strings instead — plan §6)
threw = false
try:
    enc.encode_canonical(10000000000000000000)
catch e:
    threw = true
check("huge-int-rejected", threw)

print("t01 encoding: " + str(pass["n"]) + " passed, " + str(fail["n"]) + " failed")
if fail["n"] > 0:
    raise "t01 FAILED"
