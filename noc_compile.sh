tb_name="TbNocBasic"
clean_build=false
for compile_arg in "$@"; do
    case "$compile_arg" in
        -d) clean_build=true ;;
        *) tb_name="$compile_arg" ;;
    esac
done
tb_name="${tb_name%.bsv}"

mkdir -p build
if [ "$clean_build" = true ]; then
    rm -rf build/*
fi

bsc -u -verilog -bdir build -vdir build -info-dir build -g mkNoc Noc.bsv 
bsc -u -sim -bdir build -simdir build -info-dir build -g "mk${tb_name}" "${tb_name}.bsv"
bsc -sim -bdir build -simdir build -e "mk${tb_name}" -o "build/sim${tb_name}"
"./build/sim${tb_name}"
