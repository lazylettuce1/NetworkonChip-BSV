package Noc;

import Vector    :: *;
import NocTypes  :: *;
import NocRouter :: *;

(* synthesize *)
module mkNoc (Ifc_noc);

   // Instantiate one router from your NocRouter package for every (x, y),
   // connect each router to its neighbours, and return each router's local
   // port as node[x][y].
   Integer cols = valueOf(MeshCols);
   Integer rows = valueOf(MeshRows);
   Vector#(MeshCols, Vector#(MeshRows, Ifc_noc_port)) localPorts = newVector;
   Vector#(MeshCols, Vector#(MeshRows, Ifc_noc_router)) routers = newVector;
   for (Integer x = 0; x < cols; x = x + 1) begin
      for (Integer y = 0; y < rows; y = y + 1) begin
         routers[x][y] <- mkNocRouter(NodeAddr {
            x: fromInteger(x),
            y: fromInteger(y)
         });
         localPorts[x][y] = routers[x][y].localPort;
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
