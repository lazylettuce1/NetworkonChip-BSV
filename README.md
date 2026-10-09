# Assignment 2: Network on Chip, starter files

We've provided you with a set of files to get going with your design. Note that this is in no way representative of the kind of tests that will be used in evaluation, but can act as a good starting point for you to check if you got the basic requirements right. The testbench here should exercise some basic functionality of your implementation. 

**Note that this testbench was generated with an AI agent to serve as a reference for what kinds of tests and how they would be run in the test suite. Use this with caution and care.**

| File | What it is |
|---|---|
| `NocTypes.bsv` | Parameters, packet type and interfaces. **Do not modify**: we compile against our own copy. |
| `Noc.bsv` | The `mkNoc` skeleton you fill in. |
| `TbNocBasic.bsv` | A few basic tests for `mkNoc`, to get you started. |

## Running the basic tests

Put `TbNocBasic.bsv` next to your `Noc.bsv`, `NocRouter.bsv` and `NocTypes.bsv`, then:

```
mkdir -p build
bsc -u -sim -bdir build -simdir build -info-dir build -g mkTbNocBasic TbNocBasic.bsv
bsc -sim -bdir build -simdir build -e mkTbNocBasic -o simTbNocBasic
./simTbNocBasic
```

A passing run ends with `ALL TESTS PASSED`. The run stops at the first
failure and prints a line starting with `FAIL:`, followed by the packet that
was expected and, where there is one, the packet that came out. You may use 
a waveform viewer to identify and debug problems, if any.

## What the tests do

1. **single**: one packet from (0,0) to (3,3) in an idle network.
2. **all pairs**: one packet between every ordered pair of nodes, one at a time.
3. **messages**: messages of 1, 2, ..., 8 packets from (0,0) to (3,3).
4. **stall**: a destination stops collecting for 1000 cycles while (0,0)
   sends it an 8-packet message, then starts again. This is done once for
   (3,3) and once for (1,0), its neighbour.

Every packet that comes out must equal, in all 268 bits, the one that went in.
It must come out at its `dst`, in the order it was sent, exactly once.

## What they do not do

Only one source sends at any time, so nothing here makes packets compete for
a link or a buffer. These are **not** the tests we grade with. Our test bench
also has many PEs sending at once, random traffic, back-pressure on both
sides and the extreme-load test. Passing everything here is a starting point,
not a promise of marks.

`TbNocBasic.bsv` is also not the NoC test bench you have to submit. Write your
own. You may start from this one, but you will need a smarter checker once
several sources send at the same time.
