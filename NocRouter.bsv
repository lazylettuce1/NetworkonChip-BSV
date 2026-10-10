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
   Vector#(5, FIFOF#(NocPacket)) inQ  <- replicateM(mkSizedFIFOF(8));
   Vector#(5, FIFOF#(NocPacket)) outQ <- replicateM(mkSizedFIFOF(8));
   // wires for connecting rules
   // can my input pkt ACTUALLY be routed?
   Vector#(5, Wire#(Direction)) routeWhere <- replicateM(mkDWire(Local));
   // which input is being routed?
   Vector#(5, Wire#(Direction)) pkt_dir <- replicateM(mkDWire(Local));
   Vector#(5, Reg#(Direction)) nextState <- replicateM(mkReg(North));

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
   for (Integer o = 0; o < 5; o = o + 1) begin
      Direction outputDir = unpack(fromInteger(o));
      rule rl_arbiter(outQ[o].notFull());
         Direction selectedDir = nextState[o];
         Direction checkDir = nextState[o];
         // did you find a non empty inFIFO?
         Bool found = False;
         for (Integer i = 0; i < 5; i = i + 1) begin
            Bit#(4) ix = zeroExtend(pack(nextState[o]))+fromInteger(i);
            // wrap around logic
            if (ix >= 4'd5) ix = ix - 4'd5;
            checkDir = unpack(truncate(ix));
            if (inQ[pack(checkDir)].notEmpty() && (routeWhere[pack(checkDir)] == outputDir) && !found) begin
               // if all outs are full, then just pick the last checked direction.
               selectedDir = checkDir;
               found = True;
            end
         end
         pkt_dir[o] <= selectedDir;
         // state update only happens after deq
      endrule : rl_arbiter


   end
   // you want to peek at every inFIFO
   for (Integer i = 0; i < 5; i = i + 1) begin
      rule rl_peek;
         let peeking_pkt = inQ[i].first();
         let route_dir = routeDirection(peeking_pkt.dst);
         // you can do a check without first, 
         // issue is, for first, you need diff rules,
         // but u can check routeDir without first.
         routeWhere[i] <= route_dir;
         // not checking if it can ACTUALLY be routed, just where it should go.
      endrule
   end


   for (Integer i = 0; i < 5; i = i + 1) begin
      Direction inputDir = unpack(fromInteger(i));
      for (Integer o = 0; o < 5; o = o + 1) begin
         // if in is through Y, out also must be along Y/Local
         if (i != o && ( (i == 0 && (o == 3 || o == 4)) ||
                           ( i == 3 && (o == 0 || o == 4)) ||
                           (i != 0 && i != 3 ))) begin 
            Direction outputDir = unpack(fromInteger(o));
            rule rl_transfer (
               pkt_dir[o] == inputDir && routeWhere[i] == outputDir &&
               inQ[i].notEmpty() && outQ[o].notFull()
            );
               let pkt = inQ[i].first();
               outQ[o].enq(pkt);
               inQ[i].deq();
               // update nextState for round-robin arbitration
               nextState[o] <= pkt_dir[o] == Local ? North : unpack(pack(pkt_dir[o])+1);
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
