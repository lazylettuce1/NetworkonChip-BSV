package NocRouter;

import NocTypes  :: *;
import FIFOF :: *;
import Vector :: *;

typedef enum {North, West, East, South, Local} Direction deriving (Bits, Eq);

// function to easily define a link interface between routers.
function Ifc_noc_port makeLink(
   FIFOF#(NocPacket) inFIFO,
   FIFOF#(NocPacket) outFIFO
);
   return (interface Ifc_noc_port;
      method Action ma_put_packet (NocPacket pkt); 
         inFIFO.enq(pkt);
      endmethod
      method ActionValue#(NocPacket) mav_get_packet ();
         outFIFO.deq(); 
         return outFIFO.first();
      endmethod
   endinterface);
endfunction

// declaring interfaces
interface Ifc_noc_router;
   interface Ifc_noc_port localPort;
   interface Ifc_noc_port northPort;
   interface Ifc_noc_port southPort;
   interface Ifc_noc_port eastPort;
   interface Ifc_noc_port westPort;
endinterface

(* synthesize *)
module mkNocRouter #(parameter NodeAddr myAddr) (Ifc_noc_router);
   // 5 in and out FIFOs
   Vector#(5, FIFOF#(NocPacket)) inQ  <- replicateM(mkSizedFIFOF(2));
   Vector#(5, FIFOF#(NocPacket)) outQ <- replicateM(mkSizedFIFOF(2));
   // wires for connecting rules
   // can my input pkt ACTUALLY be routed?
   Vector#(5, Wire#(Bool)) canRoute <- replicateM(mkDWire(False));
   Wire#(Direction) pkt_dir <- mkWire();
   Reg#(Direction) nextState <- mkReg(North);

   function Direction routeDirection(NodeAddr dst);
      if (dst.x > myAddr.x) begin
         return East;
      end
      else if (dst.x < myAddr.x) begin
         return West;
      end
      else if (dst.y > myAddr.y) begin
         return South;
      end
      else if (dst.y < myAddr.y) begin
         return North;
      end
      else begin
         return Local;
      end
   endfunction
   // arbiter sets the direction from which "get" needs to happen
   // "current" direction is current state.
   rule rl_arbiter;
      Direction selectedDir = nextState;
      Direction checkDir = nextState;
      Bool found = False;
      for (Integer i = 0; i < 5; i = i + 1) begin
         Bit#(4) ix = zeroExtend(pack(nextState))+fromInteger(i);
         // wrap around logic
         if (ix >= 4'd5) begin
            ix = ix - 4'd5;
         end
         checkDir = unpack(truncate(ix));
         if (inQ[pack(checkDir)].notEmpty() && !found) begin
            // if all outs are full, then just pick the last checked direction.
            selectedDir = checkDir;
            // now the peek rule, helps us check if the inFIFO's
            // first pkt can be routed to it's outFIFO.
            if (canRoute[pack(checkDir)]) begin
               found = True;
               selectedDir = checkDir;
            end
         end
      end
      pkt_dir <= selectedDir;
      // state update only happens after deq
   endrule : rl_arbiter
   // you want to peek at every inFIFO
   for (Integer i = 0; i < 5; i = i + 1) begin
      rule rl_peek;
         let peeking_pkt = inQ[i].first();
         let route_dir = routeDirection(peeking_pkt.dst);
         // you can do a check without first, 
         // issue is, for first, you need diff rules,
         // but u can check routeDir without first.
         canRoute[i] <= outQ[pack(route_dir)].notFull();
      endrule
   end


   for (Integer i = 0; i < 5; i = i + 1) begin
      Direction inputDir = unpack(fromInteger(i));
      for (Integer o = 0; o < 5; o = o + 1) begin
         if (i != o) begin 
            Direction outputDir = unpack(fromInteger(o));
            rule rl_transfer (
               pkt_dir == inputDir &&
               routeDirection(inQ[i].first().dst) == outputDir &&
               inQ[i].notEmpty() &&
               outQ[o].notFull()
            );
               let pkt = inQ[i].first();
               outQ[o].enq(pkt);
               inQ[i].deq();
               // update nextState for round-robin arbitration
               nextState <= pkt_dir == Local ? North : unpack(pack(pkt_dir)+1);
            endrule
         end
      end
   end

// defining interfaces
interface Ifc_noc_port localPort = makeLink(inQ[pack(Local)], outQ[pack(Local)]);
interface Ifc_noc_port northPort = makeLink(inQ[pack(North)], outQ[pack(North)]);
interface Ifc_noc_port southPort = makeLink(inQ[pack(South)], outQ[pack(South)]);
interface Ifc_noc_port eastPort  = makeLink(inQ[pack(East)],  outQ[pack(East)]);
interface Ifc_noc_port westPort  = makeLink(inQ[pack(West)],  outQ[pack(West)]);
endmodule

endpackage
