package TbNocRouterPerf;

import Vector :: *;
import NocTypes :: *;
import NocRouter :: *;
import NocMetrics :: *;

// B_R is an isolated capacity experiment: saturated input streams and
// continuously drained outputs. A permutation gives every input its own
// output, so this can also expose future simultaneous-forwarding designs.
(* synthesize *)
module mkTbNocRouterPerf(Empty);
   Integer cols = valueOf(MeshCols);
   Integer rows = valueOf(MeshRows);
   NodeAddr here = NodeAddr { x: fromInteger(cols / 2), y: fromInteger(rows / 2) };
   Ifc_noc_router router <- mkNocRouter(here);

   // Vector order agrees with Direction: North, West, East, South, Local.
   Vector#(5, Ifc_noc_port) ports = newVector;
   ports[0] = router.northPort;
   ports[1] = router.westPort;
   ports[2] = router.eastPort;
   ports[3] = router.southPort;
   ports[4] = router.localPort;

   function NocPacket trafficPacket(Integer inputId, UInt#(32) serial);
      NodeAddr src = here;
      NodeAddr dst = here;
      case (inputId)
         0: begin src.y = here.y - 1; end                 // North -> Local
         1: begin src.x = here.x - 1; dst.y = here.y + 1; end // West -> South
         2: begin src.x = here.x + 1; dst.x = here.x - 1; end // East -> West
         3: begin src.y = here.y + 1; dst.y = here.y - 1; end // South -> North
         4: begin dst.x = here.x + 1; end                 // Local -> East
      endcase
      Bit#(SeqWidth) seqNum = truncate(pack(serial));
      return metricPacket(src, dst, seqNum, seqNum == '1, serial);
   endfunction

   function Integer inputForOutput(Integer outputId);
      case (outputId)
         0: return 3;
         1: return 2;
         2: return 4;
         3: return 1;
         default: return 0;
      endcase
   endfunction

   Reg#(MetricCycle) cycle <- mkReg(0);
   Reg#(MetricCycle) quiet <- mkReg(0);
   Vector#(5, Reg#(MetricCount)) sent <- replicateM(mkReg(0));
   Vector#(5, Reg#(MetricCount)) received <- replicateM(mkReg(0));
   Vector#(5, Reg#(MetricCount)) sampled <- replicateM(mkReg(0));

   rule tick;
      cycle <= cycle + 1;
   endrule

   for (Integer i = 0; i < 5; i = i + 1) begin
      rule inject (cycle < fromInteger(metricWarmupCycles + metricWindowCycles));
         ports[i].ma_put_packet(trafficPacket(i, truncate(sent[i])));
         sent[i] <= sent[i] + 1;
      endrule
      rule collect;
         let pkt <- ports[i].mav_get_packet();
         let expected = trafficPacket(inputForOutput(i), truncate(received[i]));
         if (pkt != expected) begin
            $display("FAIL: B_R packet/order mismatch at output %0d, cycle %0d", i, cycle);
            $display("Expected: ", fshow(expected));
            $display("Received: ", fshow(pkt));
            $finish(1);
         end
         received[i] <= received[i] + 1;
         if (cycle >= fromInteger(metricWarmupCycles) &&
             cycle < fromInteger(metricWarmupCycles + metricWindowCycles))
            sampled[i] <= sampled[i] + 1;
      endrule
   end

   rule finish (cycle >= fromInteger(metricWarmupCycles + metricWindowCycles));
      Bool drained = True;
      MetricCount sampleCount = 0;
      for (Integer i = 0; i < 5; i = i + 1) begin
         if (received[i] != sent[inputForOutput(i)]) drained = False;
         sampleCount = sampleCount + sampled[i];
      end
      if (drained) begin
         quiet <= quiet + 1;
         if (quiet == fromInteger(metricQuietCycles)) begin
            reportBandwidth("B_R", sampleCount, fromInteger(metricWindowCycles));
            $display("PASS: B_R warmup=%0d window=%0d; every accepted packet drained",
                     metricWarmupCycles, metricWindowCycles);
            $finish(0);
         end
      end
      else quiet <= 0;

      if (cycle >= fromInteger(metricWarmupCycles + metricWindowCycles + metricDrainTimeout)) begin
         $display("FAIL: B_R did not drain; bandwidth is not a valid passing result");
         $finish(1);
      end
   endrule
endmodule

endpackage
