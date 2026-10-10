package NocRouterFlit;

import NocTypes  :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
import Vector :: *;

// Repeat the 12-bit packet header on each half; tail marks the second half.
typedef struct {
   NodeAddr src;
   NodeAddr dst;
   Bool is_last;
   Bit#(SeqWidth) seq_num;
   Bool tail;
   Bit#(128) payload;
} NocFlit deriving (Bits, Eq, FShow);

interface Ifc_flit_port;
   method Action ma_put_packet(NocFlit flit);
   method ActionValue#(NocFlit) mav_get_packet();
endinterface

typedef enum {North, West, East, South, Local} Direction deriving (Bits, Eq);

// function to easily define a link interface between routers.
function Ifc_flit_port makeLink(
   FIFOF#(NocFlit) inFIFO,
   FIFOF#(NocFlit) outFIFO
);
   return (interface Ifc_flit_port;
      method Action ma_put_packet (NocFlit pkt); 
         inFIFO.enq(pkt);
      endmethod
      method ActionValue#(NocFlit) mav_get_packet ();
         outFIFO.deq(); 
         return outFIFO.first();
      endmethod
   endinterface);
endfunction

// declaring interfaces
interface Ifc_flit_router;
   interface Ifc_flit_port localPort;
   interface Ifc_flit_port northPort;
   interface Ifc_flit_port southPort;
   interface Ifc_flit_port eastPort;
   interface Ifc_flit_port westPort;
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
module mkFlitRouter #(parameter NodeAddr myAddr) (Ifc_flit_router);
   // Registered inputs break the combinational path between router hops.
   Vector#(5, FIFOF#(NocFlit)) inQ <- replicateM(mkSizedFIFOF(2));
   // Empty bypass outputs can enqueue and be collected in the same cycle.
Vector#(5, FIFOF#(NocFlit)) outQ <- replicateM(mkSizedBypassFIFOF(2));
   // wires for connecting rules
   // can my input pkt ACTUALLY be routed?
   Vector#(5, Wire#(Direction)) routeWhere <- replicateM(mkDWire(Local));
   // One grant bit per input, for each output. Zero means no transfer.
   Vector#(5, Wire#(Bit#(5))) grants <- replicateM(mkDWire(0));
   // Inputs after the previous winner get priority; zero wraps to North.
   Vector#(5, Reg#(Bit#(5))) priorityMask <- replicateM(mkReg(0));
   // A head reserves its output until the matching tail is transferred.
   Vector#(5, Reg#(Bool)) locked <- replicateM(mkReg(False));
   Vector#(5, Reg#(Bit#(5))) owner <- replicateM(mkReg(0));

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
         grants[o] <= locked[o] ? owner[o] :
                      (maskedRequests != 0 ? preferredGrant : fallbackGrant);
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
               if (pkt.tail) begin
                  locked[o] <= False;
                  priorityMask[o] <= nextMask;
               end
               else begin
                  locked[o] <= True;
                  owner[o] <= inputGrant;
               end
            endrule
         end
      end
   end

// defining interfaces
interface Ifc_flit_port localPort = makeLink(inQ[pack(Local)], outQ[pack(Local)]);
interface Ifc_flit_port northPort = makeLink(inQ[pack(North)], outQ[pack(North)]);
interface Ifc_flit_port southPort = makeLink(inQ[pack(South)], outQ[pack(South)]);
interface Ifc_flit_port eastPort  = makeLink(inQ[pack(East)],  outQ[pack(East)]);
interface Ifc_flit_port westPort  = makeLink(inQ[pack(West)],  outQ[pack(West)]);
endmodule

(* synthesize *)
module mkNocFlit (Ifc_noc);

   // Instantiate one router from your NocRouter package for every (x, y),
   // connect each router to its neighbours, and return each router's local
   // port as node[x][y].
   Integer cols = valueOf(MeshCols);
   Integer rows = valueOf(MeshRows);
   Vector#(MeshCols, Vector#(MeshRows, Ifc_noc_port)) localPorts = newVector;
   Vector#(MeshCols, Vector#(MeshRows, Ifc_flit_router)) routers = newVector;
   for (Integer x = 0; x < cols; x = x + 1) begin
      for (Integer y = 0; y < rows; y = y + 1) begin
         routers[x][y] <- mkFlitRouter(NodeAddr {
            x: fromInteger(x),
            y: fromInteger(y)
         });
         // Packet interfaces stay unchanged at the PEs. Only links carry flits.
         FIFOF#(NocPacket) injectQ <- mkPipelineFIFOF;
         FIFOF#(NocPacket) collectQ <- mkBypassFIFOF;
         Reg#(Bool) sendTail <- mkReg(False);
         Reg#(Bool) haveHead <- mkReg(False);
         Reg#(Bit#(128)) headPayload <- mkReg(0);

         rule rl_serialize;
            let pkt = injectQ.first();
            NocFlit flit = NocFlit {
               src: pkt.src, dst: pkt.dst, is_last: pkt.is_last,
               seq_num: pkt.seq_num, tail: sendTail,
               payload: sendTail ? pkt.payload[255:128] : pkt.payload[127:0]
            };
            routers[x][y].localPort.ma_put_packet(flit);
            sendTail <= !sendTail;
            if (sendTail) injectQ.deq();
         endrule

         rule rl_receiveHead (!haveHead);
            let flit <- routers[x][y].localPort.mav_get_packet();
            headPayload <= flit.payload;
            haveHead <= True;
         endrule

         rule rl_receiveTail (haveHead);
            let flit <- routers[x][y].localPort.mav_get_packet();
            collectQ.enq(NocPacket {
               src: flit.src, dst: flit.dst, is_last: flit.is_last,
               seq_num: flit.seq_num, payload: {flit.payload, headPayload}
            });
            haveHead <= False;
         endrule

         localPorts[x][y] = interface Ifc_noc_port;
            method Action ma_put_packet(NocPacket pkt);
               injectQ.enq(pkt);
            endmethod
            method ActionValue#(NocPacket) mav_get_packet();
               let pkt = collectQ.first();
               collectQ.deq();
               return pkt;
            endmethod
         endinterface;
      end
   end
   for (Integer x = 0; x < cols; x = x + 1) begin
      for (Integer y = 0; y < rows; y = y + 1) begin
         // first instantiate the router, then connect it to its neighbours
         if (x > 0) begin
            rule rl_moveWest;
               let pkt <- routers[x][y].westPort.mav_get_packet();
               routers[x-1][y].eastPort.ma_put_packet(pkt);
            endrule
         end
         if (x+1 < cols) begin
            rule rl_moveEast;
               let pkt <- routers[x][y].eastPort.mav_get_packet();
               routers[x+1][y].westPort.ma_put_packet(pkt);
            endrule
         end
         if (y > 0) begin
            rule rl_moveNorth;
               let pkt <- routers[x][y].northPort.mav_get_packet();
               routers[x][y-1].southPort.ma_put_packet(pkt);
            endrule
         end
         if ( y+1 < rows) begin
            rule rl_moveSouth;
               let pkt <- routers[x][y].southPort.mav_get_packet();
               routers[x][y+1].northPort.ma_put_packet(pkt);
            endrule
         end
      end
   end
   interface node = localPorts;
   // start from top left, connect to right, and bottom

endmodule


endpackage
