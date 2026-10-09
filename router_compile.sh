mkdir -p build-router
rm -rf build-router/*

bsc -u -verilog -bdir build-router -vdir build-router -info-dir build-router -g mkNocRouter NocRouter.bsv 
bsc -u -sim -bdir build-router -simdir build-router -info-dir build-router -g mkTbNocRouter TbNocRouter.bsv
bsc -sim -bdir build-router -simdir build-router -e mkTbNocRouter -o build-router/simTbNocRouter
./build-router/simTbNocRouter
