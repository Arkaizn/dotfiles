// Unit tests for services/lib/*.js (plain `.pragma library` files).
// Run: node tests/lib.test.mjs
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"
import assert from "node:assert/strict"

const lib = join(dirname(fileURLToPath(import.meta.url)), "..", "services", "lib")
function load(name) {
    const ctx = vm.createContext({})
    vm.runInContext(readFileSync(join(lib, name), "utf8").replace(/^\.pragma library/m, ""), ctx)
    return ctx
}

let failed = 0, passed = 0
function test(name, fn) {
    try { fn(); passed++ } catch (e) { failed++; console.log("FAIL " + name + "\n  " + e.message) }
}

const Valid = load("Valid.js")
test("host accepts names and addresses", () => {
    for (const h of ["example.com", "router", "192.168.0.1", "::1", "fe80::1", "a-b.c"]) assert.equal(Valid.host(h), "", h)
})
test("host refuses options and junk", () => {
    assert.notEqual(Valid.host("-oProxyCommand=x"), "")
    assert.notEqual(Valid.host(""), "")
    assert.notEqual(Valid.host("256.1.1.1"), "")
    assert.notEqual(Valid.host("a b"), "")
})
test("port range", () => {
    assert.equal(Valid.port("22"), "")
    assert.notEqual(Valid.port("0"), "")
    assert.notEqual(Valid.port("65536"), "")
    assert.notEqual(Valid.port("2x"), "")
})
test("name (themes, profiles)", () => {
    assert.equal(Valid.name("Work 2_a-b"), "")
    assert.equal(Valid.name("  Gaming "), "")
    assert.equal(Valid.name(""), "enter a name")
    assert.notEqual(Valid.name("../x"), "")
    assert.notEqual(Valid.name("x".repeat(41)), "")
})

const JsonCheck = load("JsonCheck.js")
test("JsonCheck.parse matches JSON.parse", () => {
    const t = '{ "a": [1, 2.5, -3e2, true, null], "b": { "c": "x\\n\\u00e9" } }'
    assert.deepEqual(JSON.parse(JSON.stringify(JsonCheck.parse(t).value)), JSON.parse(t))
})
test("JsonCheck.parse reports the line of an error", () => {
    let err = null
    try { JsonCheck.parse('{\n  "a": 1,\n  "b": }') } catch (e) { err = e }
    assert.ok(err, "should throw")
    assert.equal(err.line, 3)
})

const Format = load("Format.js")
test("bytes (decimal)", () => {
    assert.equal(Format.bytes(0), "0 B")
    assert.equal(Format.bytes(999), "999 B")
    assert.equal(Format.bytes(1500), "1.5 KB")
    assert.equal(Format.bytes(250e9), "250 GB")
})
test("ibytes (binary)", () => {
    assert.equal(Format.ibytes(1024), "1.0 KiB")
    assert.equal(Format.ibytes(1536 * 1024 * 1024), "1.5 GiB")
    assert.equal(Format.ibytes(200 * 1024), "200 KiB")
})

console.log(passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)
