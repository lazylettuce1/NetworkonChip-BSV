package TbNocRouter;

import NocTypes  :: *;
import NocRouter :: *;
import StmtFSM   :: *;
import NocMetrics :: *;

// A standalone test of one router at (1,1).
// Compile: bsc -u -sim -bdir build -simdir build -info-dir build -g mkTbNocRouter TbNocRouter.bsv
// Link:    bsc -sim -bdir build -simdir build -e mkTbNocRouter -o build/simTbNocRouter
// Run:     ./build/simTbNocRouter

function NocPacket testPacket(NodeAddr src, NodeAddr dst,
                              Bit#(PayloadWidth) payload);
   return NocPacket {
      src: src, dst: dst, seq_num: 0, is_last: True, payload: payload
   };
endfunction

function Action checkPacket(NocPacket expected, NocPacket received);
   return action
      if (received != expected) begin
         $display("FAIL: packet changed or arrived in the wrong test");
         $display("Expected: ", fshow(expected));
         $display("Received: ", fshow(received));
         $finish(1);
      end
   endaction;
endfunction

(* synthesize *)
module mkTbNocRouter(Empty);
   NodeAddr here = NodeAddr { x: 1, y: 1 };
   Ifc_noc_router router <- mkNocRouter(here);
   Ifc_latency_metric routerLatency <- mkLatencyMetric("router_latency");

   // Unique payloads let us compare the complete packet in every test.
   NocPacket eastPkt = testPacket(here, NodeAddr { x: 2, y: 2 }, 'hE);
   NocPacket westPkt = testPacket(here, NodeAddr { x: 0, y: 1 }, 'hB);
   NocPacket northPkt = testPacket(here, NodeAddr { x: 1, y: 0 }, 'hA);
   NocPacket southPkt = testPacket(here, NodeAddr { x: 1, y: 2 }, 'hD);
   NocPacket localPkt = testPacket(NodeAddr { x: 1, y: 0 }, here, 'hC);

   Reg#(UInt#(16)) cycle <- mkReg(0);
   rule watchdog;
      cycle <= cycle + 1;
      if (cycle == 200) begin
         $display("FAIL: timeout; check routing and FIFO readiness guards");
         $finish(1);
      end
   endrule

   Stmt tests = seq

      $display("TEST: PE -> West");
      action
         router.localPort.ma_put_packet(westPkt);
         routerLatency.ma_injected(zeroExtend(cycle));
      endaction
      action
         let received <- router.westPort.mav_get_packet();
         checkPacket(westPkt, received);
         routerLatency.ma_collected(zeroExtend(cycle));
      endaction

      $display("TEST: PE -> North");
      router.localPort.ma_put_packet(northPkt);
      action
         let received <- router.northPort.mav_get_packet();
         checkPacket(northPkt, received);
      endaction
      
      $display("TEST: PE -> East; X must take priority over Y");
      router.localPort.ma_put_packet(eastPkt);
      // No consumer calls "get" during these cycles; the packet must be held.
      delay(10);
      action
         let received <- router.eastPort.mav_get_packet();
         checkPacket(eastPkt, received);
      endaction

      $display("TEST: PE -> South");
      router.localPort.ma_put_packet(southPkt);
      action
         let received <- router.southPort.mav_get_packet();
         checkPacket(southPkt, received);
      endaction

      $display("TEST: North -> PE; destination is this router");
      router.northPort.ma_put_packet(localPkt);
      action
         let received <- router.localPort.mav_get_packet();
         checkPacket(localPkt, received);
      endaction

      $display("PASS: five routes, unchanged packets, and delayed collection");
      $finish(0);
   endseq;

   mkAutoFSM(tests);
endmodule

endpackage
