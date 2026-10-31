import base64
import re


def mutf7_decode(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "&":
            j = s.index("-", i)
            if j == i + 1:
                out.append("&")
            else:
                b = s[i + 1:j].replace(",", "/")
                b += "=" * (-len(b) % 4)
                out.append(base64.b64decode(b).decode("utf-16-be"))
            i = j + 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def mutf7_encode(s):
    out, buf = [], []

    def flush():
        if buf:
            b = base64.b64encode("".join(buf).encode("utf-16-be")).decode().rstrip("=").replace("/", ",")
            out.append("&" + b + "-")
            buf.clear()
    for ch in s:
        if 0x20 <= ord(ch) <= 0x7e:
            flush()
            out.append("&-" if ch == "&" else ch)
        else:
            buf.append(ch)
    flush()
    return "".join(out)


def quote_box(path):
    p = mutf7_encode(path)
    return '"' + p.replace("\\", "\\\\").replace('"', '\\"') + '"'


class Lit(bytes):
    pass


def chunks_of(data):
    """imaplib's data list -> a flat list of bytes pieces and Lit literals"""
    out = []
    for item in data:
        if item is None:
            continue
        if isinstance(item, tuple):
            out.append(item[0])
            out.append(Lit(item[1]))
        else:
            out.append(item)
    return out


def tokenize(chunks):
    toks = []
    for c in chunks:
        if isinstance(c, Lit):
            toks.append(c)
            continue
        s = c.decode("utf-8", "replace") if isinstance(c, bytes) else c
        i, n = 0, len(s)
        while i < n:
            ch = s[i]
            if ch in " \r\n":
                i += 1
            elif ch in "()":
                toks.append(ch)
                i += 1
            elif ch == '"':
                j, buf = i + 1, []
                while j < n and s[j] != '"':
                    if s[j] == "\\" and j + 1 < n:
                        j += 1
                    buf.append(s[j])
                    j += 1
                toks.append(("str", "".join(buf)))
                i = j + 1
            elif ch == "{":
                j = s.index("}", i)
                i = j + 1          # the literal follows as its own chunk
            else:
                j, depth = i, 0
                while j < n:
                    cj = s[j]
                    if cj == "[":
                        depth += 1
                    elif cj == "]":
                        depth -= 1
                    elif depth == 0 and (cj in " ()\r\n"):
                        break
                    j += 1
                toks.append(("atom", s[i:j]))
                i = j
    return toks


def parse_tokens(toks):
    """-> nested python lists; atoms as str, strings as str, literals as bytes, NIL as None"""
    pos = 0

    def value():
        nonlocal pos
        t = toks[pos]
        pos += 1
        if t == "(":
            items = []
            while toks[pos] != ")":
                items.append(value())
            pos += 1
            return items
        if isinstance(t, Lit):
            return bytes(t)
        kind, v = t
        if kind == "atom" and v.upper() == "NIL":
            return None
        return v
    out = []
    while pos < len(toks):
        if toks[pos] == ")":
            pos += 1
            continue
        out.append(value())
    return out


def parse_fetch(data):
    """FETCH answer -> [{KEY: value}] (keys upper case, BODY[...] kept as written)"""
    vals = parse_tokens(tokenize(chunks_of(data)))
    msgs, i = [], 0
    while i < len(vals):
        if isinstance(vals[i], str) and vals[i].isdigit() and i + 1 < len(vals) and vals[i + 1] == "FETCH":
            i += 2
            continue
        if isinstance(vals[i], list):
            items, d = vals[i], {}
            for k in range(0, len(items) - 1, 2):
                key = items[k]
                if isinstance(key, str):
                    key = re.sub(r"^BODY\.PEEK", "BODY", key.upper())
                    d[key] = items[k + 1]
            msgs.append(d)
        i += 1
    return msgs


def parse_list(data):
    out = []
    for item in data:
        if item is None:
            continue
        vals = parse_tokens(tokenize(chunks_of([item])))
        if len(vals) < 3:
            continue
        flags, delim, name = vals[0] or [], vals[1], vals[2]
        if isinstance(name, bytes):
            name = name.decode("utf-8", "replace")
        out.append({"flags": [f.lower() for f in flags if isinstance(f, str)], "delim": delim or "/", "raw": str(name)})
    return out


def uid_set(uids):
    """[3, 4, 5, 9] -> '3:5,9'"""
    uids = sorted(set(int(u) for u in uids))
    parts, i = [], 0
    while i < len(uids):
        j = i
        while j + 1 < len(uids) and uids[j + 1] == uids[j] + 1:
            j += 1
        parts.append(str(uids[i]) if i == j else f"{uids[i]}:{uids[j]}")
        i = j + 1
    return ",".join(parts)
