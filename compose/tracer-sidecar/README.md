# tracer-sidecar

`tracer-sidecar` reads and processes cardano-node logs from disk, line by line, and is able to
write antithesis [assertions](https://antithesis.com/docs/properties_assertions/) to `$ANTITHESIS_OUTPUT_DIR/sdk.jsonl`.

The idea is to use it to test properties that a Cardano network should satisfy, as well as
using sometimes-assertions to guide the fuzzer into finding more interesting scenarios more often.
