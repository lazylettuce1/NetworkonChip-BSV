package TbNocBuffer;

import NocTypes :: *;
import NocRouter :: *;
import StmtFSM :: *;

function NocPacket eastPacket(Bit#(SeqWidth) seqNum);
   return NocPacket {
      src: NodeAddr { x: 0, y: 1 },
      dst: NodeAddr { x: 3, y: 1 },
      seq_num: seqNum, is_last: seqNum == 2,
      payload: zeroExtend(seqNum)
   };
endfunction

// Check output fall-through latency, then full-buffer backpressure and ordering.
(* synthesize *)
module mkTbNocBuffer(Empty);
   Ifc_noc_router router <- mkNocRouter(NodeAddr { x: 2, y: 1 });
   NocPacket northPacket = NocPacket {
      src: NodeAddr { x: 2, y: 1 },
      dst: NodeAddr { x: 2, y: 0 },
      seq_num: 0, is_last: True, payload: '1
   };
   NocPacket probePacket = NocPacket {
      src: NodeAddr { x: 2, y: 1 },
      dst: NodeAddr { x: 3, y: 1 },
      seq_num: 0, is_last: True, payload: 'hA7
   };
`ifdef NOC_BUFFERED_OUTPUTS
   Integer expectedLatency = 2;
`else
   Integer expectedLatency = 1;
`endif
   Reg#(UInt#(16)) cycle <- mkReg(0);
   Reg#(UInt#(16)) injectedCycle <- mkReg(0);
   Reg#(Bool) probeSeen <- mkReg(False);
   Reg#(Bool) releaseEast <- mkReg(True);
   Reg#(Bool) northSeen <- mkReg(False);
   Reg#(UInt#(4)) eastReceived <- mkReg(0);

   rule watchdog;
      cycle <= cycle + 1;
      if (cycle == 200) begin
         $display("FAIL: buffer test timeout");
         $finish(1);
      end
   endrule

   rule collectNorth;
      let pkt <- router.northPort.mav_get_packet();
      if (northSeen || pkt != northPacket) begin
         $display("FAIL: North packet changed or duplicated");
         $finish(1);
      end
      northSeen <= True;
      $display("[%0d] North packet collected; East released = %0d", cycle, releaseEast);
   endrule

   rule collectEast (releaseEast);
      let pkt <- router.eastPort.mav_get_packet();
      if (eastReceived == 0) begin
         let latency = cycle - injectedCycle;
         if (pkt != probePacket || latency != fromInteger(expectedLatency)) begin
            $display("FAIL: probe changed or latency %0d differs from expected %0d",
                     latency, expectedLatency);
            $finish(1);
         end
         probeSeen <= True;
         $display("No-load router latency: %0d cycles", latency);
      end
      else if (eastReceived >= 4 ||
               pkt != eastPacket(truncate(pack(eastReceived - 1)))) begin
         $display("FAIL: East packets changed, duplicated, or reordered");
         $finish(1);
      end
      eastReceived <= eastReceived + 1;
   endrule

   Stmt tests = seq
      $display("TEST: output bypass latency and backpressure");
      action
         router.localPort.ma_put_packet(probePacket);
         injectedCycle <= cycle;
      endaction
      await(probeSeen);
      releaseEast <= False;
      // Stop collecting while a three-packet flow fills output/input buffers.
      router.westPort.ma_put_packet(eastPacket(0));
      router.westPort.ma_put_packet(eastPacket(1));
      router.westPort.ma_put_packet(eastPacket(2));
      delay(5);
      // An independent Local -> North transfer must still make progress.
      router.localPort.ma_put_packet(northPacket);
      delay(5);
      action
         if (!northSeen) begin
            $display("FAIL: blocked East prevented an independent North transfer");
            $finish(1);
         end
         $display("North progressed while East remained blocked");
      endaction
      releaseEast <= True;
      await(northSeen && eastReceived == 4);
      delay(5);
      $display("PASS: latency, backpressure, unchanged packets, ordered flow, full drain");
      $finish(0);
   endseq;
   mkAutoFSM(tests);
endmodule

endpackage
