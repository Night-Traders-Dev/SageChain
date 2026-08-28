# orbit/crypto/encoding.sage — canonical serialization (plan §52 step 1, §21)
# Orbit Blockchain | Protocol v1 | Status: implemented
#
# Deterministic encoding used for EVERY hash and signature input.
# Rules:
#   nil    -> "n"
#   bool   -> "b0" | "b1"
#   number -> "i<integral-decimal>e"   (fractional floats are REJECTED)
#   string -> "s<len>:<bytes>"
#   array  -> "l" items... "e"
#   dict   -> "d" (enc(key) enc(value))... "e"   [keys sorted lexicographically]
#
# No dictionary iteration order and no runtime formatting ever reach a hash.

proc sort_strings(arr):
    # insertion sort — deterministic, no reliance on builtin ordering
    let n = len(arr)
    let a = arr
    var i = 1
    while i < n:
        let cur = a[i]
        var j = i - 1
        while j >= 0 and a[j] > cur:
            a[j + 1] = a[j]
            j = j - 1
        a[j + 1] = cur
        i = i + 1
    return a

proc _enc_num(v):
    # integral check without float tricks: value must equal its truncated form
    if v != int(v):
        raise "canonical encoding rejects non-integral numbers"
    if v >= 9007199254740992:
        raise "canonical encoding rejects integers above 2^53 (use bigint strings)"
    return "i" + str(int(v)) + "e"

proc encode_canonical(v):
    let t = type(v)
    if v == nil:
        return "n"
    if t == "bool":
        if v:
            return "b1"
        return "b0"
    if t == "number":
        return _enc_num(v)
    if t == "string":
        return "s" + str(len(v)) + ":" + v
    if t == "array":
        let parts = ["l"]
        for item in v:
            push(parts, encode_canonical(item))
        push(parts, "e")
        return join(parts, "")
    if t == "dict":
        let keys = []
        for k in v:
            push(keys, k)
        let sorted_keys = sort_strings(keys)
        let parts = ["d"]
        for k in sorted_keys:
            push(parts, encode_canonical(k))
            push(parts, encode_canonical(v[k]))
        push(parts, "e")
        return join(parts, "")
    raise "canonical encoding: unsupported type '" + t + "'"

# Convenience: canonical bytes of a record, immediately hashed
from crypto.hash import sha256_hex

proc canonical_hash(v):
    return sha256_hex(encode_canonical(v))

# Simple decoder for the subset used in keystore
proc decode_canonical(s):
    let idx = {"i": 0}
    proc _parse():
        if idx["i"] >= len(s):
            raise "decode: unexpected end"
        let c = s[idx["i"]]
        idx["i"] = idx["i"] + 1
        if c == "n":
            return nil
        if c == "b":
            let b = s[idx["i"]]
            idx["i"] = idx["i"] + 1
            return b == "1"
        if c == "i":
            let start = idx["i"]
            while idx["i"] < len(s) and s[idx["i"]] != "e":
                idx["i"] = idx["i"] + 1
            let num_str = slice(s, start, idx["i"])
            idx["i"] = idx["i"] + 1
            return int(num_str)
        if c == "s":
            let start = idx["i"]
            while idx["i"] < len(s) and s[idx["i"]] != ":":
                idx["i"] = idx["i"] + 1
            let len_str = slice(s, start, idx["i"])
            idx["i"] = idx["i"] + 1
            let ln = int(len_str)
            let val = slice(s, idx["i"], idx["i"] + ln)
            idx["i"] = idx["i"] + ln
            return val
        if c == "l":
            let arr = []
            while idx["i"] < len(s) and s[idx["i"]] != "e":
                push(arr, _parse())
            idx["i"] = idx["i"] + 1
            return arr
        if c == "d":
            let obj = {}
            while idx["i"] < len(s) and s[idx["i"]] != "e":
                let k = _parse()
                let v = _parse()
                obj[k] = v
            idx["i"] = idx["i"] + 1
            return obj
        raise "decode: unknown type " + c
    let result = _parse()
    if idx["i"] != len(s):
        raise "decode: trailing data"
    return result
