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
   Vector#(5, FIFOF#(NocPacket)) inQ  <- replicateM(mkFIFOF);
   Vector#(5, FIFOF#(NocPacket)) outQ <- replicateM(mkFIFOF);
   // wires for connecting rules
   Wire#(Direction) pkt_dir <- mkWire();
   Reg#(Direction) nextState <- mkReg(North);

   // function Direction priorityArbiter();
   //    Direction dir = Local;
   //    if      (inQ[pack(North)].notEmpty()) dir = North;
   //    else if (inQ[pack(West)].notEmpty())  dir = West;
   //    else if (inQ[pack(East)].notEmpty())  dir = East;
   //    else if (inQ[pack(South)].notEmpty()) dir = South;
   //    else if (inQ[pack(Local)].notEmpty()) dir = Local;

   //    return dir;
   // endfunction

   // // which side to choose?
   // // only care about incoming data -> "get"
   // rule rl_arbiter( inQ[pack(North)].notEmpty() ||
   //                  inQ[pack(West)].notEmpty()  ||
   //                  inQ[pack(East)].notEmpty()  ||
   //                  inQ[pack(South)].notEmpty() ||
   //                  inQ[pack(Local)].notEmpty());
   //    // arbiter sets the direction from which "get" needs to happen
   //    pkt_dir <= priorityArbiter();
   // endrule : rl_arbiter

   // which side to choose?
   // only care about incoming data -> "get"
   rule rl_arbiter;
      // arbiter sets the direction from which "get" needs to happen
      // "current" direction is current state.
      Direction selectedDir = nextState;
      Direction checkDir = nextState;
      Bool found = False;
      for (Integer i = 0; i < 5; i = i + 1) begin
         Bit#(4) ix = zeroExtend(pack(nextState))+fromInteger(i);
         if (ix >= 4'd5) begin
            ix = ix - 4'd5;
         end
         checkDir = unpack(truncate(ix));
         if (inQ[pack(checkDir)].notEmpty() && !found) begin
            found = True;
            selectedDir = checkDir;
         end
      end
      pkt_dir <= selectedDir;
      // state update only happens after deq
   endrule : rl_arbiter

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
   
   rule rl_router;
      // get the next packet from the arbiter   
      let pkt = inQ[pack(pkt_dir)].first();
      let pkt_dst = pkt.dst;
      let route_dir = routeDirection(pkt_dst);
      if (outQ[pack(route_dir)].notFull()) begin
         outQ[pack(route_dir)].enq(pkt);
         inQ[pack(pkt_dir)].deq();
         // update nextState for round-robin arbitration
         nextState <= pkt_dir == Local ? North : unpack(pack(pkt_dir)+1);
      end
   endrule : rl_router


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

            nextState <= inputDir == Local
                        ? North
                        : unpack(pack(inputDir) + 1);
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
