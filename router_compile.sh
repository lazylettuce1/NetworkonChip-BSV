tb_name="TbNocRouter"
clean_build=false
for compile_arg in "$@"; do
    case "$compile_arg" in
        -d) clean_build=true ;;
        *) tb_name="$compile_arg" ;;
    esac
done
tb_name="${tb_name%.bsv}"

mkdir -p build-router
if [ "$clean_build" = true ]; then
    rm -rf build-router/*
fi

bsc -u -verilog -bdir build-router -vdir build-router -info-dir build-router -g mkNocRouter NocRouter.bsv 
bsc -u -sim -bdir build-router -simdir build-router -info-dir build-router -g "mk${tb_name}" "${tb_name}.bsv"
bsc -sim -bdir build-router -simdir build-router -e "mk${tb_name}" -o "build-router/sim${tb_name}"
"./build-router/sim${tb_name}"
