mkdir -p build
rm -rf build/*

bsc -u -verilog -bdir build -vdir build -info-dir build -g mkNoc Noc.bsv 
bsc -u -sim -bdir build -simdir build -info-dir build -g mkTbNocBasic TbNocBasic.bsv
bsc -sim -bdir build -simdir build -e mkTbNocBasic -o build/simTbNocBasic
./build/simTbNocBasic
