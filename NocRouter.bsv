package NocRouter;

import NocTypes  :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
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

// Select the lowest numbered requesting input. Zero means no grant.
function Bit#(5) priorityEncode(Bit#(5) requests);
   Bit#(5) grant = 0;
   Bool found = False;
   for (Integer i = 0; i < 5; i = i + 1) begin
      if (requests[i] == 1 && !found) begin
         grant[i] = 1;
         found = True;
      end
   end
   return grant;
endfunction

(* synthesize *)
module mkNocRouter #(parameter NodeAddr myAddr) (Ifc_noc_router);
   // Registered inputs break the combinational path between router hops.
   Vector#(5, FIFOF#(NocPacket)) inQ <- replicateM(mkSizedFIFOF(2));
   // Empty bypass outputs can enqueue and be collected in the same cycle.
`ifdef NOC_BUFFERED_OUTPUTS
   Vector#(5, FIFOF#(NocPacket)) outQ <- replicateM(mkSizedFIFOF(2));
`elsif NOC_BYPASS_DEPTH2
   Vector#(5, FIFOF#(NocPacket)) outQ <- replicateM(mkSizedBypassFIFOF(2));
`else
   // Best measured bandwidth/area: depth-1 bypass outputs (default).
   Vector#(5, FIFOF#(NocPacket)) outQ <- replicateM(mkBypassFIFOF);
`endif
   // wires for connecting rules
   // can my input pkt ACTUALLY be routed?
   Vector#(5, Wire#(Direction)) routeWhere <- replicateM(mkDWire(Local));
   // One grant bit per input, for each output. Zero means no transfer.
   Vector#(5, Wire#(Bit#(5))) grants <- replicateM(mkDWire(0));
   // Inputs after the previous winner get priority; zero wraps to North.
   Vector#(5, Reg#(Bit#(5))) priorityMask <- replicateM(mkReg(0));

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
   
   // Each output independently grants one input using masked round robin.
   for (Integer o = 0; o < 5; o = o + 1) begin
      Direction outputDir = unpack(fromInteger(o));
      rule rl_arbiter(outQ[o].notFull());
         Bit#(5) requests = 0;
         for (Integer i = 0; i < 5; i = i + 1) begin
            // Request only connections present in the XY transfer rules.
            if (i != o && ( (i == 0 && (o == 3 || o == 4)) ||
                           ( i == 3 && (o == 0 || o == 4)) ||
                           (i != 0 && i != 3 ))) begin
               requests[i] = pack(inQ[i].notEmpty() &&
                                  routeWhere[i] == outputDir);
            end
         end
         Bit#(5) maskedRequests = requests & priorityMask[o];
         let preferredGrant = priorityEncode(maskedRequests);
         let fallbackGrant = priorityEncode(requests);
         grants[o] <= maskedRequests != 0 ? preferredGrant : fallbackGrant;
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
      Bit#(5) inputGrant = 5'b00001 << i;
      for (Integer o = 0; o < 5; o = o + 1) begin
         // if in is through Y, out also must be along Y/Local
         if (i != o && ( (i == 0 && (o == 3 || o == 4)) ||
                           ( i == 3 && (o == 0 || o == 4)) ||
                           (i != 0 && i != 3 ))) begin 
            Direction outputDir = unpack(fromInteger(o));
            rule rl_transfer (
               // Whole-grant equality makes the winners mutually exclusive.
               grants[o] == inputGrant && routeWhere[i] == outputDir &&
               inQ[i].notEmpty() && outQ[o].notFull()
            );
               let pkt = inQ[i].first();
               outQ[o].enq(pkt);
               inQ[i].deq();
               // This mask is constant for input i. Advance only on transfer.
               Bit#(5) nextMask = 5'b11111;
               for (Integer j = 0; j <= i; j = j + 1) begin
                  nextMask[j] = 0;
               end
               priorityMask[o] <= nextMask;
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
