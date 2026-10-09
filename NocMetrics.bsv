package NocMetrics;

import NocTypes :: *;
import Vector :: *;

// Testbench helpers only: no router or NoC implementation belongs here.
typedef UInt#(32) MetricCycle;
typedef UInt#(64) MetricCount;

// Change these together for all sustained-bandwidth experiments.
`ifdef METRIC_WARMUP
Integer metricWarmupCycles = `METRIC_WARMUP;
`else
Integer metricWarmupCycles = 1000;
`endif
`ifdef METRIC_WINDOW
Integer metricWindowCycles = `METRIC_WINDOW;
`else
Integer metricWindowCycles = 10000;
`endif
Integer metricDrainTimeout = 10000;
Integer metricQuietCycles = 32;
`ifdef METRIC_SEED
Integer metricSeed = `METRIC_SEED;
`else
Integer metricSeed = 1;
`endif

// Print the exact numerator/denominator as well as a truncated decimal rate.
function Action reportBandwidth(String name, MetricCount packets,
                                MetricCycle cycles);
   return action
      MetricCount bytes = packets * fromInteger(valueOf(PayloadBytes));
      MetricCount duration = zeroExtend(cycles);
      if (duration == 0) begin
         $display("FAIL: %s has a zero-cycle measurement window", name);
         $finish(1);
      end
      else begin
         MetricCount whole = bytes / duration;
         MetricCount fraction = ((bytes % duration) * 1000) / duration;
         // Bluesim does not zero-pad %03d like printf. Print each digit.
         $display("--- %s = %0d.%0d%0d%0d bytes/cycle ---",
                  name, whole,
                  fraction / 100, (fraction / 10) % 10, fraction % 10);
         $display("    %0d packets | %0d payload bytes | %0d cycles",
                  packets, bytes, cycles);
      end
   endaction;
endfunction

interface Ifc_latency_metric;
   method Action ma_injected(MetricCycle cycle);
   method Action ma_collected(MetricCycle cycle);
endinterface

// Record the first injection and first collection only. RWire observations
// let both events be recorded in one cycle without adding a register stage.
module mkLatencyMetric#(String name)(Ifc_latency_metric);
   RWire#(MetricCycle) injected <- mkRWire;
   RWire#(MetricCycle) collected <- mkRWire;
   Reg#(Bool) started <- mkReg(False);
   Reg#(Bool) finished <- mkReg(False);
   Reg#(MetricCycle) firstInjection <- mkReg(0);

   rule record;
      let putEvent = injected.wget;
      let getEvent = collected.wget;
      Bool haveStart = started || isValid(putEvent);
      MetricCycle startCycle = started ? firstInjection : fromMaybe(0, putEvent);
      if (!started && isValid(putEvent)) begin
         started <= True;
         firstInjection <= fromMaybe(0, putEvent);
      end
      if (!finished && haveStart && isValid(getEvent)) begin
         MetricCycle endCycle = fromMaybe(0, getEvent);
         $display("--- %s = %0d cycles ---", name, endCycle - startCycle);
         $display("    Injected: cycle %0d | Collected: cycle %0d",
                  startCycle, endCycle);
         finished <= True;
      end
   endrule

   method Action ma_injected(MetricCycle cycle);
      injected.wset(cycle);
   endmethod
   method Action ma_collected(MetricCycle cycle);
      collected.wset(cycle);
   endmethod
endmodule

typedef struct {
   MetricCycle cycle;
   Bool isLast;
} StreamCollection deriving (Bits, Eq);

interface Ifc_stream_metric;
   method Action ma_start();
   method Action ma_collected(MetricCycle cycle, Bool isLast);
endinterface

module mkStreamMetric#(Integer expectedPackets)(Ifc_stream_metric);
   PulseWire start <- mkPulseWire;
   RWire#(StreamCollection) collected <- mkRWire;
   Reg#(Bool) armed <- mkReg(False);
   Reg#(MetricCount) packetCount <- mkReg(0);
   Reg#(MetricCycle) firstCollection <- mkReg(0);

   rule record;
      Bool nextArmed = armed;
      MetricCount nextCount = packetCount;
      MetricCycle nextFirst = firstCollection;
      if (start) begin
         nextArmed = True;
         nextCount = 0;
      end
      if (nextArmed && isValid(collected.wget)) begin
         let sample = fromMaybe(?, collected.wget);
         if (nextCount == 0) nextFirst = sample.cycle;
         nextCount = nextCount + 1;
         if (sample.isLast) begin
            if (nextCount != fromInteger(expectedPackets)) begin
               $display("FAIL: B_S expected %0d packets, collected %0d",
                        expectedPackets, nextCount);
               $finish(1);
            end
            else begin
               reportBandwidth("B_S", nextCount, sample.cycle - nextFirst + 1);
            end
            nextArmed = False;
         end
      end
      armed <= nextArmed;
      packetCount <= nextCount;
      firstCollection <= nextFirst;
   endrule

   method Action ma_start();
      start.send;
   endmethod
   method Action ma_collected(MetricCycle cycle, Bool isLast);
      collected.wset(StreamCollection { cycle: cycle, isLast: isLast });
   endmethod
endmodule

// Deterministic packet contents for performance-test correctness checks.
function NocPacket metricPacket(NodeAddr src, NodeAddr dst,
                                Bit#(SeqWidth) seqNum, Bool isLast,
                                UInt#(32) messageId);
   Vector#(TDiv#(TAdd#(PayloadWidth, 31), 32), Bit#(32)) words = newVector;
   Bit#(32) seed = pack(messageId) ^ zeroExtend({pack(src), pack(dst), seqNum});
   for (Integer i = 0; i < valueOf(TDiv#(TAdd#(PayloadWidth, 31), 32)); i = i + 1)
      words[i] = seed ^ (fromInteger(i + 1) * 32'h9e3779b9);
   return NocPacket { src: src, dst: dst, seq_num: seqNum,
                      is_last: isLast, payload: truncate(pack(words)) };
endfunction

function Bit#(32) nextMetricRandom(Bit#(32) state);
   Bit#(32) value = state;
   value = value ^ (value << 13);
   value = value ^ (value >> 17);
   value = value ^ (value << 5);
   return value;
endfunction

endpackage
